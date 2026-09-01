#!/usr/bin/env bash
# distro/alarm.sh — Arch Linux ARM (aarch64) 实现
# 契约:distro_base_packages / distro_setup_repos / distro_kernel_packages /
# distro_post_install(同 arch.sh/cachyos.sh)+ 可选 distro_host_preflight
# (主入口 declare -F 守卫调用,dry-run 门后、动磁盘前)。
#
# 跨架构要点(依据 docs/superpowers/specs/2026-09-01-archlinuxarm-support-design.md §3):
# - pacstrap 无 --arch:跨架构 = pacstrap -C <bootstrap conf>(Architecture=aarch64)
#   + -M(不拷宿主 mirrorlist);-K 保留——pacstrap 源码实测(:208-218):-K 只对
#   目标 keyring 做 --init,安装期包验签走宿主 keyring(故 preflight 第 2 步
#   必须先把 alarm 构建密钥导入宿主 keyring)
# - alarm 仓库数据库不签名(上游设计,非镜像问题):SigLevel=Required DatabaseOptional
# - chroot 内 aarch64 二进制经 binfmt_misc(qemu-aarch64-static,F flag)执行
# - mkinitcpio autodetect 在 qemu-user 下读到的是宿主 x86_64 /sys,RK3588 专有
#   驱动进不了 initramfs(eMMC/SD 必死)→ 安装期临时移除、post_install 恢复。
#   恢复的原因:删 autodetect 不是 alarm 官方做法(其 mkinitcpio 包不 patch
#   mkinitcpio.conf),真机上的后续内核更新需要 autodetect 正确裁剪

# pacstrap 的自定义 pacman.conf 路径,由 distro_host_preflight 生成;
# modules/base.sh 读此变量,非空则追加 -C/-M
PACSTRAP_CONF=""

# alarm 构建密钥(签名所有 alarm 包;archlinuxarm 官方文档 + keyring 包核实)
_ALARM_BUILD_KEY=68B3537F39A313B3E574D06777193F152BDBE6A6

# 镜像地址:MY_ALARM_MIRROR 为空用 geo 默认;值含 $arch/$repo 占位符(此处转义)
_alarm_mirror() {
    echo "${MY_ALARM_MIRROR:-https://mirror.archlinuxarm.org/\$arch/\$repo}"
}

# alarm 四仓库段:bootstrap(Server= 直写)与目标内正式配置(Include mirrorlist)共用
_alarm_repo_sections() {
    local inc=$1
    cat <<EOF

[core]
$inc

[extra]
$inc

[alarm]
$inc

[aur]
$inc
EOF
}

distro_host_preflight() {
    # 1) binfmt_misc:qemu-aarch64 必须已注册、enabled、带 F flag(注册时打开
    #    解释器文件,chroot 内无需拷 qemu-aarch64-static;无 F 则 chroot 内
    #    执行 aarch64 二进制直接 Exec format error)
    local bf=/proc/sys/fs/binfmt_misc/qemu-aarch64
    [[ -f $bf ]] || die "binfmt_misc 未注册 qemu-aarch64 —— 宿主安装: sudo pacman -S qemu-user-static qemu-user-static-binfmt"
    [[ $(head -1 "$bf") == enabled ]] || die "binfmt qemu-aarch64 未 enabled(见 $bf)"
    grep -q '^flags:.*F' "$bf" \
        || die "binfmt qemu-aarch64 缺 F flag(fix_binary),chroot 内无法执行 aarch64 二进制"

    # 2) 宿主 keyring 导入 alarm 构建密钥(pacstrap 安装期验签走宿主 keyring;
    #    与 cachyos keyring 同手法。注意:这是对宿主 keyring 的持久改动,README 已写明)
    log "宿主 keyring 导入 alarm 构建密钥"
    pacman-key --recv-keys "$_ALARM_BUILD_KEY"
    pacman-key --lsign-key "$_ALARM_BUILD_KEY"

    # 3) bootstrap pacman.conf(pacstrap -C 用;临时文件统一放 .tmp/,不入库)
    mkdir -p "$SCRIPT_DIR/.tmp"
    PACSTRAP_CONF="$SCRIPT_DIR/.tmp/alarm-bootstrap-pacman.conf"
    log "生成 bootstrap pacman.conf: $PACSTRAP_CONF(mirror: $(_alarm_mirror))"
    {
        cat <<'EOF'
[options]
HoldPkg = pacman glibc
Architecture = aarch64
CheckSpace
# alarm 仓库数据库不签名是上游设计(非镜像问题)
SigLevel = Required DatabaseOptional
ParallelDownloads = 5
EOF
        _alarm_repo_sections "Server = $(_alarm_mirror)"
    } >"$PACSTRAP_CONF"
}

distro_base_packages() {
    # 无 efifs(alarm 仓库无此包,包页 404)→ XBOOTLDR 在 alarm 下是 FAT32,
    # systemd-boot 原生可读;btrfs-progs 必须在(内核安装触发 mkinitcpio 的
    # fsck hook,缺 btrfsck 非零退出,同 arch.sh 注释);archlinuxarm-keyring
    # 显式列入:distro_setup_repos 的 --populate 需要它提供的官方 keyring 文件,
    # 不赌 base 组的传递依赖
    echo "base archlinuxarm-keyring linux-firmware btrfs-progs iptables-nft"
}

distro_setup_repos() {
    # pacstrap 用的是 bootstrap conf(-C);目标内 /etc/pacman.conf 是 alarm
    # pacman 包出厂内容,覆写为确定形态(幂等;宿主侧直接写,同 pacman.sh:52 手法)
    log "alarm 仓库配置(mirror: $(_alarm_mirror))"
    chroot_write_file /etc/pacman.d/mirrorlist <<<"Server = $(_alarm_mirror)"
    {
        cat <<'EOF'
[options]
HoldPkg = pacman glibc
Architecture = aarch64
CheckSpace
SigLevel = Required DatabaseOptional
ParallelDownloads = 5
# 与 alarm 出厂 pacman.conf 对齐(真机 aarch64 原生内核支持 Landlock,
# 下载沙箱正常工作);构建期 qemu-user 下沙箱不可用,由 chroot 内 pacman
# 调用的 --disable-sandbox CLI flag 兜底(见 lib/chroot.sh pacman_install
# 与下方 -Syu),不污染此配置。DownloadUser 构建期保持注释(qemu-user 下
# 沙箱必死,见 base.sh 同款处理);distro_post_install 恢复为出厂生效值
#DownloadUser = alpm
Color
UseSyslog
VerbosePkgLists
EOF
        _alarm_repo_sections "Include = /etc/pacman.d/mirrorlist"
    } >"$MNT_DIR/etc/pacman.conf"

    # keyring:--init 已由 pacstrap -K 完成(目标 keyring 已有本地 master key);
    # --populate 导入 archlinuxarm-keyring 包的官方 keyring(master×3 + 构建密钥)
    # 并 lsign。qemu-user 下 gpg 明显变慢(分钟级),属预期
    chroot_run pacman-key --populate archlinuxarm
    # --disable-sandbox:qemu-user 不翻译 Landlock/seccomp syscall,pacman 7.1
    # 下载沙箱(由 DownloadUser=alpm 触发)在模拟 chroot 内必失败(实测)
    chroot_run pacman -Syu --noconfirm --disable-sandbox
}

distro_kernel_packages() {
    # 全局变量契约(主入口必须当前 shell 调用,子 shell 丢赋值);
    # linux-aarch64 产出 /boot/Image + /boot/initramfs-linux.img(无 vmlinuz-*)
    KERNEL_PKG=linux-aarch64
    KERNEL_PKGS="linux-aarch64 linux-aarch64-headers"

    # mkinitcpio 是内核包的依赖,此时尚未安装(/etc/mkinitcpio.conf 不存在,
    # 实测 cp 报 No such file or directory);且内核安装的
    # 90-mkinitcpio-install hook 在同事务内就用该 conf 建 initramfs——
    # 必须先显式装 mkinitcpio 再改它的 conf
    pacman_install mkinitcpio

    # 临时移除 autodetect(原因见文件头注释;备份恢复法,不做双向 sed——
    # 二次字符串拼接太脆弱)。distro_post_install 负责恢复
    cp "$MNT_DIR/etc/mkinitcpio.conf" "$MNT_DIR/etc/mkinitcpio.conf.alarm-orig"
    sed -i 's/^\(HOOKS=.*\)autodetect /\1/' "$MNT_DIR/etc/mkinitcpio.conf"
    if ! grep -q '^HOOKS=' "$MNT_DIR/etc/mkinitcpio.conf" \
        || grep '^HOOKS=' "$MNT_DIR/etc/mkinitcpio.conf" | grep -q autodetect; then
        die "mkinitcpio.conf 移除 autodetect 失败(HOOKS 行缺失或形态变化?)"
    fi
}

distro_post_install() {
    # 1) 恢复 autodetect:镜像内 initramfs 已是安装期生成的完整版;此后真机上的
    #    内核更新在真实 RK3588 硬件上跑 mkinitcpio,autodetect 正常裁剪。
    #    中间无其他模块改 mkinitcpio.conf(全仓 grep 核实),整文件恢复安全
    mv "$MNT_DIR/etc/mkinitcpio.conf.alarm-orig" "$MNT_DIR/etc/mkinitcpio.conf"

    # 1.5) 恢复 DownloadUser=alpm(构建期禁用的下载沙箱;base.sh 注释出厂
    #    conf + 本文件 setup_repos 的覆写 conf 注释,两处都已被后续覆盖/重写,
    #    这里只需处理最终生效的这份。真机 aarch64 原生内核有 Landlock,
    #    沙箱正常工作,与 alarm 出厂 conf 对齐)
    sed -i 's/^#DownloadUser = alpm/DownloadUser = alpm/' "$MNT_DIR/etc/pacman.conf"
    grep -q '^DownloadUser = alpm' "$MNT_DIR/etc/pacman.conf" \
        || die "恢复 DownloadUser=alpm 失败(pacman.conf 形态变化?)"

    # 2) DTB override 通道:内核包自带 dtb → edk2-rk3588 约定路径 /efi/dtb/base/
    #    (固件优先加载它再做 fix-up)。缺文件 warn 不 die:固件经 EFI config
    #    table 提供的内置 fix-up DTB 可兜底。引导项不写 devicetree 行——
    #    bootloader 侧覆盖会丢固件 fix-up
    local dtb="$MNT_DIR/boot/dtbs/rockchip/rk3588-orangepi-5-plus.dtb"
    if [[ -f $dtb ]]; then
        mkdir -p "$MNT_DIR/efi/dtb/base"
        cp "$dtb" "$MNT_DIR/efi/dtb/base/"
    else
        warn "内核包未带 rk3588-orangepi-5-plus.dtb,跳过 /efi/dtb override(固件内置 DTB 兜底)"
    fi
}
