#!/usr/bin/env bash
# modules/ime.sh — fcitx5 输入法 + Rime(桌面必需)
# rime-ice-git 来自 archlinuxcn 源 → mod_requires pacman
# Wayland 下无需环境变量(text-input 协议);XWayland 应用的 GTK_IM_MODULE 等
# 环境变量属用户配置,放 dotfiles / ~/.config/uwsm/env,不在此处理

mod_requires() { echo pacman; }
mod_before() { echo desktop-kde desktop-niri; }

mod_install() {
    pacman_install fcitx5 fcitx5-rime fcitx5-configtool fcitx5-qt fcitx5-gtk \
        fcitx5-nord rime-ice-git
}
