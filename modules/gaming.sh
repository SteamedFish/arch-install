#!/usr/bin/env bash
# modules/gaming.sh — 游戏栈(可选)
# wine/steam 系需要 multilib 源 → mod_requires pacman(pacman 模块已开 multilib)
# an-anime-game-launcher-bwrap 在 [archlinuxcn] 源(pacman 模块保证该源存在)
# ananicy-cpp 仅在 CachyOS 启用:用户在 Arch 上遇到 ananicy-cpp.service 问题,
# 而 CachyOS 的 cachyos-settings 自带配套调优规则(distro/cachyos.sh 装)

mod_requires() { echo pacman; }

mod_install() {
    pacman_install flatpak lutris proton wine wine-gecko wine-mono
    # 纯依赖定位(--asdeps,避免被当成显式安装)
    chroot_run pacman -S --asdeps --needed --noconfirm mangohud gamescope gamemode
    # 以下包仅在 [archlinuxcn]:
    pacman_install an-anime-game-launcher-bwrap

    if [[ $DISTRO == cachyos ]]; then
        pacman_install ananicy-cpp
        # CachyOS 官方游戏元包:applications 拉常用工具(反作弊/Gamemode 客户端等),
        # meta 拉 Steam/Lutris/Heroic 等启动器。Arch 上无对应仓库路径,仅在此安装。
        pacman_install cachyos-gaming-applications cachyos-gaming-meta
        chroot_enable ananicy-cpp.service
    else
        log "跳过 ananicy-cpp 与 cachyos-gaming-*(仅 CachyOS 启用;Arch 上该服务有问题,且仓库无对应元包)"
    fi
}
