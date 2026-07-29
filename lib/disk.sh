#!/usr/bin/env bash
# lib/disk.sh — 安装目标识别、分区、格式化、挂载、引导安装、cleanup
# 分区方案(与原脚本一致,符合 systemd DPS,systemd-repart 可直接扩容):
#   p1 EFI System   256MiB fat32 → /efi
#   p2 XBOOTLDR     1GiB   ext4  → /boot
#   p3 Linux root   剩余   btrfs,subvol ArchLinux(rootflags=subvol=/ArchLinux)
# 全局输出:TARGET_TYPE LOOP_DEV PART_EFI PART_XBOOT PART_ROOT MNT_DIR

MNT_DIR=${MNT_DIR:-/mnt}

# 分区设备名:/dev/sda→/dev/sda1;/dev/loop0、/dev/nvme0n1、/dev/mmcblk0→p1
_part_dev() {
    local dev=$1 n=$2
    if [[ $dev =~ (loop|nvme|mmcblk) ]]; then
        printf '%sp%s' "$dev" "$n"
    else
        printf '%s%s' "$dev" "$n"
    fi
}

detect_target_type() {
    if [[ -b $TARGET ]]; then
        TARGET_TYPE=disk
    elif [[ -f $TARGET || $TARGET == *.img || $TARGET == *.raw ]]; then
        TARGET_TYPE=image
    else
        die "无法识别目标类型: $TARGET(既不是块设备,也不像镜像文件)"
    fi
    log "目标类型: $TARGET_TYPE"
}

prepare_target() {
    if [[ $TARGET_TYPE == image ]]; then
        if [[ ! -f $TARGET ]]; then
            log "创建镜像: $TARGET ($SIZE)"
            # 稀疏文件:ls 看到 $SIZE,实际只占已写入的块(du 才是真实占用),
            # 既留足扩容余量又不浪费宿主机磁盘(原为 preallocation=full 全量分配)
            qemu-img create -f raw -o preallocation=off "$TARGET" "$SIZE" >/dev/null
        else
            warn "镜像已存在,将被重新分区: $TARGET"
        fi
        LOOP_DEV=$(losetup -fP --show "$TARGET")
        partprobe "$LOOP_DEV"
        PART_EFI=$(_part_dev "$LOOP_DEV" 1)
        PART_XBOOT=$(_part_dev "$LOOP_DEV" 2)
        PART_ROOT=$(_part_dev "$LOOP_DEV" 3)
        log "loop 设备: $LOOP_DEV"
    else
        # 占用检查:挂载点与打开句柄
        if lsblk -no MOUNTPOINT "$TARGET" | grep -q .; then
            [[ $FORCE == 1 ]] || die "$TARGET 存在已挂载的分区,拒绝继续(--force 可覆盖)"
            warn "$TARGET 有已挂载分区,--force 继续"
        fi
        if lsof "$TARGET" >/dev/null 2>&1; then
            [[ $FORCE == 1 ]] || die "$TARGET 正被进程使用(lsof),拒绝继续(--force 可覆盖)"
            warn "$TARGET 正被使用,--force 继续"
        fi
        if [[ $FORCE != 1 ]]; then
            lsblk "$TARGET"
            local ans
            read -rp "将抹掉 $TARGET 上的全部分区和数据,输入 yes 继续: " ans
            [[ $ans == yes ]] || die "用户取消"
        fi
        PART_EFI=$(_part_dev "$TARGET" 1)
        PART_XBOOT=$(_part_dev "$TARGET" 2)
        PART_ROOT=$(_part_dev "$TARGET" 3)
    fi
}

partition_and_mount() {
    local dev=$TARGET
    [[ $TARGET_TYPE == image ]] && dev=$LOOP_DEV
    log "分区: $dev"
    sfdisk --no-reread "$dev" <<_EOF_
label: gpt
unit: sectors
size=256MiB, name="EFI System", type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B
size=1GiB, name="Linux extended boot", attrs="LegacyBIOSBootable", type=BC13C2FF-59E6-4262-A352-B275FD6F7172
name="Linux root (x86-64)", type=4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709
_EOF_
    partprobe "$dev" 2>/dev/null || true
    sleep 1

    log "格式化"
    mkfs.fat -n "EFI" -F 32 "$PART_EFI" >/dev/null
    mkfs.ext4 -F -L "Linux Boot" "$PART_XBOOT" >/dev/null
    mkfs.btrfs -f -L "Linux Root" "$PART_ROOT" >/dev/null

    mkdir -p "$MNT_DIR"
    mount "$PART_ROOT" "$MNT_DIR"
    btrfs subvolume create "$MNT_DIR"/ArchLinux >/dev/null
    umount "$MNT_DIR"

    mount -o subvol=ArchLinux,noatime,compress=zstd "$PART_ROOT" "$MNT_DIR"
    mkdir -p "$MNT_DIR"/efi "$MNT_DIR"/boot
    mount -o noatime "$PART_EFI" "$MNT_DIR"/efi
    mount -o noatime "$PART_XBOOT" "$MNT_DIR"/boot
}

install_bootloader() {
    log "安装 systemd-boot"
    chroot_run bootctl --esp-path=/efi --boot-path=/boot --no-variables install

    # efifs 驱动(让 systemd-boot 直接读 btrfs/ext4),base 模块保证 efifs 已装
    if [[ -d $MNT_DIR/usr/lib/efifs-x64 ]]; then
        mkdir -p "$MNT_DIR"/efi/EFI/systemd/drivers/
        cp "$MNT_DIR"/usr/lib/efifs-x64/{ext2_x64.efi,btrfs_x64.efi} \
            "$MNT_DIR"/efi/EFI/systemd/drivers/
    fi

    cat >"$MNT_DIR"/efi/loader/loader.conf <<EOF
default @saved
timeout 5
console-mode max
EOF

    local uuid ucode_line=""
    uuid=$(blkid -s UUID -o value "$PART_ROOT")
    # 微码 initrd 必须在内核 initramfs 之前;CPUTYPE 由主入口解析(--cputype 可覆盖)
    if [[ -n ${CPUTYPE:-} && $CPUTYPE != generic ]]; then
        ucode_line="initrd  /${CPUTYPE}-ucode.img"
    fi

    # 引导项按发行版命名:CachyOS 内核包 linux-cachyos[-变体] 产生
    # /boot/vmlinuz-linux-cachyos[-变体] 与 initramfs-linux-cachyos[-变体][-fallback].img,
    # 与 Arch 的 vmlinuz-linux 不同,不能复用 arch.conf
    local name title
    if [[ ${DISTRO:-arch} == cachyos ]]; then
        name=cachyos; title="CachyOS"
    else
        name=arch; title="Arch Linux"
    fi
    mkdir -p "$MNT_DIR"/boot/loader/entries/
    # MY_KERNEL_PARAMS:追加的自定义内核参数(如 ttm.pages_limit 调 GTT,见 config.example.sh)
    local kparams=""
    [[ -n ${MY_KERNEL_PARAMS:-} ]] && kparams=" $MY_KERNEL_PARAMS"
    cat >"$MNT_DIR"/boot/loader/entries/$name.conf <<EOF
title   $title
linux   /vmlinuz-$KERNEL_PKG
$ucode_line
initrd  /initramfs-$KERNEL_PKG.img
options root=UUID=$uuid rootfstype=btrfs rootflags=subvol=/ArchLinux mitigations=off add_efi_memmap rw$kparams
EOF
    # fallback 条目只在对应 initramfs 存在时写:CachyOS 内核 preset 只有
    # default(实测无 initramfs-*-fallback.img,cachyos-hooks 包也不提供 preset),
    # 写了会是指向不存在文件的坏条目;Arch 官方内核 preset 有 fallback,正常生成
    if [[ -f $MNT_DIR/boot/initramfs-$KERNEL_PKG-fallback.img ]]; then
        cat >"$MNT_DIR"/boot/loader/entries/$name-fallback.conf <<EOF
title   $title (fallback initramfs)
linux   /vmlinuz-$KERNEL_PKG
$ucode_line
initrd  /initramfs-$KERNEL_PKG-fallback.img
options root=UUID=$uuid rootfstype=btrfs rootflags=subvol=/ArchLinux mitigations=off add_efi_memmap rw$kparams
EOF
    fi
}

cleanup_target() {
    # 镜像最终清一次包缓存(配合 pacman_install 的每次 -Sc,防止镜像臃肿)
    if [[ ${TARGET_TYPE:-} == image && -d $MNT_DIR/usr/bin ]]; then
        # 原脚本 cleanup:rm -rf 整个缓存目录(比 -Scc 更彻底;
        # 同时清掉 pacstrap 阶段及 download-* 残留)
        rm -rf "${MNT_DIR}/var/cache/pacman/pkg"
        # 把已删除块 punch 回稀疏文件(否则清出的空间仍占宿主机磁盘)
        fstrim "$MNT_DIR" 2>/dev/null || true
    fi
    if mountpoint -q "$MNT_DIR" 2>/dev/null; then
        umount -R "$MNT_DIR" 2>/dev/null || umount -R --lazy "$MNT_DIR"
    fi
    if [[ -n ${LOOP_DEV:-} ]]; then
        losetup -d "$LOOP_DEV" 2>/dev/null || true
    fi
}
