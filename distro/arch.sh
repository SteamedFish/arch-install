#!/usr/bin/env bash
# distro/arch.sh — 原版 Arch 实现

distro_base_packages() {
    # btrfs-progs 必须随 pacstrap 进:内核安装触发 mkinitcpio 时若缺 btrfsck,
    # fsck hook 报 No fsck helpers found 并使 pacman 以"构建有错"退出(实测)
    echo "base linux-firmware efifs iptables-nft btrfs-progs"
}

distro_setup_repos() {
    # pacman.conf 调整、archlinuxcn 等统一由 pacman 模块负责
    :
}

distro_kernel_packages() {
    KERNEL_PKG=linux
    KERNEL_PKGS="linux linux-headers"
}

distro_post_install() {
    :
}
