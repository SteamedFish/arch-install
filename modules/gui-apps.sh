#!/usr/bin/env bash
# modules/gui-apps.sh — 非必需 GUI 应用(可选:--extra-modules gui-apps)
# 只含官方源包。AUR 包(如 stabilitymatrix、linuxqq、feishu-bin 等)
# 请装完系统后用 yay 自行安装或放 config/hooks.sh
# 依赖 desktop profile 提供的显示服务器;qt5ct/qt6ct 主题工具放这里

mod_install() {
    pacman_install tokodon firefox firefox-i18n-zh-cn kgpg okular flameshot \
        neochat telegram-desktop element-desktop yakuake \
        android-tools ark dolphin dolphin-plugins discord kamera karchive kate \
        smplayer gwenview haruna emacs-wayland \
        qt5ct qt6ct languagetool
}
