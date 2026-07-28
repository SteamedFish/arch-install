#!/usr/bin/env bash
# modules/pacman.sh — pacman.conf 调整、mirrorlist(需求 6)、archlinuxcn 源
# 读取变量:MIRRORLIST(copy|original|reflector|config)、MY_MIRRORLIST_FILE(config 模式)
# 提供:archlinuxcn 源(ime 的 rime-ice-git、gaming 的多媒体包依赖它)

mod_install() {
    log "pacman.conf 调整"
    chroot_run sed -i 's/^#Color/Color/' /etc/pacman.conf
    chroot_run sed -i 's/^#VerbosePkgLists/VerbosePkgLists/' /etc/pacman.conf
    # multilib(wine/steam 等 32 位依赖需要)
    chroot_run sed -i '/^#\[multilib\]/ { s/^#//; n; /^#Include/ s/^#// }' /etc/pacman.conf

    log "mirrorlist: $MIRRORLIST"
    case $MIRRORLIST in
        copy)
            cp /etc/pacman.d/mirrorlist "${MNT_DIR}/etc/pacman.d/mirrorlist"
            ;;
        original)
            # 官方默认全量列表,取消所有 Server 注释,由 pacman 按顺序试
            curl -fsSL 'https://archlinux.org/mirrorlist/all/' \
                | sed 's/^#Server/Server/' >"${MNT_DIR}/etc/pacman.d/mirrorlist"
            ;;
        reflector)
            # 在宿主机用 reflector 生成后写入目标(需求 6)
            command -v reflector &>/dev/null \
                || die "--mirrorlist reflector 需要宿主机安装 reflector: sudo pacman -S reflector"
            reflector --country China --age 12 --protocol https --sort rate \
                --save "${MNT_DIR}/etc/pacman.d/mirrorlist"
            ;;
        config)
            [[ -n ${MY_MIRRORLIST_FILE:-} && -f ${MY_MIRRORLIST_FILE:-} ]] \
                || die "--mirrorlist config 需要 config.sh 中 MY_MIRRORLIST_FILE 指向存在的文件"
            cp "$MY_MIRRORLIST_FILE" "${MNT_DIR}/etc/pacman.d/mirrorlist"
            ;;
        *) die "未知 mirrorlist 模式: $MIRRORLIST" ;;
    esac

    log "archlinuxcn 源"
    # 固定镜像地址,不再依赖宿主机的 archcn-mirrorlist(可移植性)
    chroot_write_file /etc/pacman.d/archcn-mirrorlist <<'EOF'
Server = https://repo.archlinuxcn.org/$arch
EOF
    # 先 TrustAll 装上 keyring 再恢复严格验签(keyring 包自身无法验签的鸡生蛋问题)
    cat >>"${MNT_DIR}/etc/pacman.conf" <<'EOF'

[archlinuxcn]
SigLevel = Optional TrustAll
Include = /etc/pacman.d/archcn-mirrorlist
EOF
    chroot_run pacman -Syu --noconfirm
    pacman_install archlinuxcn-keyring
    chroot_run sed -i 's/^SigLevel = Optional/#&/' /etc/pacman.conf
}
