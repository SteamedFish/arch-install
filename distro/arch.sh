#!/usr/bin/env bash
# distro/arch.sh — 原版 Arch 实现

distro_base_packages() {
    echo "base linux-firmware efifs iptables-nft"
}

distro_setup_repos() {
    # pacman.conf 调整、archlinuxcn 等统一由 pacman 模块负责
    :
}

distro_kernel_packages() {
    KERNEL_PKG=linux
    echo "linux linux-headers"
}

distro_post_install() {
    :
}
