#!/usr/bin/env bash
# lib/chroot.sh — arch-chroot 封装。模块只允许通过这些函数操作目标系统。
# 依赖变量:MNT_DIR(由 lib/disk.sh 设置)

chroot_run() {
    arch-chroot "$MNT_DIR" "$@"
}

# pacman_install [--asdeps] pkg...
# 每次安装后清理旧版本缓存(pacman -Sc)——VM 镜像空间有限,见 plan 追加决策 3
pacman_install() {
    chroot_run pacman -S --needed --noconfirm "$@"
    # 先删中断下载的 download-* 残留(文件或目录都有可能,实测均出现):
    # -Sc 会逐一读取缓存包校验,读到半截的临时文件报 Error reading fd 7
    # 并以非零退出
    rm -rf "$MNT_DIR"/var/cache/pacman/pkg/download-*
    chroot_run pacman -Sc --noconfirm
}

# chroot_write_file /abs/path — 从 stdin 写入目标系统内文件(自动建目录)
chroot_write_file() {
    local path=$1
    mkdir -p "${MNT_DIR}$(dirname "$path")"
    cat >"${MNT_DIR}${path}"
}

# chroot_enable svc1 svc2 ...
chroot_enable() {
    chroot_run systemctl enable "$@"
}
