#!/usr/bin/env bash
# modules/gui-apps.sh — 非必需 GUI 应用(可选:--extra-modules gui-apps)
# 只含官方源包。AUR 包(如 stabilitymatrix、linuxqq、feishu-bin 等)
# 请装完系统后用 yay 自行安装或放 config/hooks.sh
# 依赖 desktop profile 提供的显示服务器;qt5ct/qt6ct 主题工具放这里

mod_install() {
    # DE 无关应用 + KDE 原生社交客户端(neochat/tokodon 自动拉入 KF6 deps,
    # 放进这里以便 niri 用户也能用——见 desktop-kde.sh 注释)
    # emacs-wayland:官方包 29+ 即 pgtk + native-comp,替代 archlinuxcn 的 emacs-native-comp-pgtk-git
    pacman_install firefox firefox-i18n-zh-cn telegram-desktop element-desktop \
        discord android-tools emacs-wayland haruna smplayer flameshot \
        qt5ct qt6ct languagetool \
        neochat tokodon
    # CachyOS 专有:Firefox 性能/隐私调优(只有 [cachyos] 仓库有,Arch 上不可用)
    if [[ ${DISTRO:-arch} == cachyos ]]; then
        pacman_install cachyos-firefox-settings
    fi
}
