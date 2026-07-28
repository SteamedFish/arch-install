#!/usr/bin/env bash
# modules/gui-apps.sh — 非必需 GUI 应用(可选:--extra-modules gui-apps)
# 只含官方源包。AUR 包(如 stabilitymatrix、linuxqq、feishu-bin 等)
# 请装完系统后用 yay 自行安装或放 config/hooks.sh
# 依赖 desktop profile 提供的显示服务器;qt5ct/qt6ct 主题工具放这里

mod_install() {
    # 只放 DE 无关应用;KDE 专属应用收拢在 desktop-kde 模块
    # emacs-wayland:官方包 29+ 即 pgtk + native-comp,替代 archlinuxcn 的 emacs-native-comp-pgtk-git
    pacman_install firefox firefox-i18n-zh-cn telegram-desktop element-desktop \
        discord android-tools emacs-wayland haruna smplayer flameshot \
        qt5ct qt6ct languagetool
}
