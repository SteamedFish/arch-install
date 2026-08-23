#!/usr/bin/env bash
# distro/arch.sh — 原版 Arch 实现

distro_base_packages() {
    # btrfs-progs 必须随 pacstrap 进:内核安装触发 mkinitcpio 时若缺 btrfsck,
    # fsck hook 报 No fsck helpers found 并使 pacman 以"构建有错"退出(实测)
    # iptables-nft 仅为 docker 保留(运行时调 iptables 命令建 NAT 链;移除会让后装
    # docker 时 pacman 按字母序挑 provider)。防火墙本体已迁 nftables(modules/firewall.sh)
    echo "base linux-firmware efifs iptables-nft btrfs-progs"
}

distro_setup_repos() {
    # 启用 multilib(wine/steam 等 32 位依赖需要;此处无条件启用,
    # 不依赖 pacman 模块是否加载——gaming 之外用到 32 位包的场景
    # 也都能用)。原 pacman 模块里的同名 sed 已下放,见 commit message。
    sed -i '/^#\[multilib\]/ { s/^#//; n; /^#Include/ s/^#// }' "$MNT_DIR/etc/pacman.conf"
}

distro_kernel_packages() {
    KERNEL_PKG=linux
    KERNEL_PKGS="linux linux-headers"
}

distro_post_install() {
    :
}
