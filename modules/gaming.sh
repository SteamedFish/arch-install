#!/usr/bin/env bash
# modules/gaming.sh — 游戏栈(可选)
# wine/steam 系需要 multilib 源 → mod_requires pacman(pacman 模块已开 multilib)
# an-anime-game-launcher-bwrap 等在 AUR,请装完后用 yay 或 hooks 处理
# enable 服务:ananicy-cpp.service(进程优先级自动调度)

mod_requires() { echo pacman; }

mod_install() {
    pacman_install flatpak lutris proton wine wine-gecko wine-mono \
        mangohud gamescope gamemode ananicy-cpp
    chroot_enable ananicy-cpp.service
}
