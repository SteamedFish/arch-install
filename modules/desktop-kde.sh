#!/usr/bin/env bash
# modules/desktop-kde.sh — KDE Plasma(Wayland)+ sddm(迁移期保留)
# 依赖:audio fonts ime network-nm(resolver 闭包)
# 读取变量:MY_GREETER_AUTOLOGIN(1=autologin 到 plasma,仅家中台式机)、MY_USERNAME
# enable 服务:sddm.service、polkit.service

mod_requires() { echo audio fonts ime network-nm; }
mod_conflicts() { echo desktop-niri; }

mod_install() {
    pacman_install plasma-meta plasma-desktop sddm-kcm konsole xorg-xwayland \
        kdeconnect bluedevil xclip wl-clipboard
    # KDE 专属应用(依赖 KDE 框架);社交聊天客户端(KDE 原生但按用途归类)
    # 移到 gui-apps,niri 用户也能用——KF6 deps 随包自动拉入
    pacman_install dolphin dolphin-plugins kate ark okular kgpg yakuake \
        gwenview kamera karchive kio-admin \
        ffmpegthumbs kdegraphics-thumbnailers
    # CachyOS 专有:KDE 设置包与 Nord 主题(官方安装器同款,仅 [cachyos] 库有)
    if [[ ${DISTRO:-arch} == cachyos ]]; then
        pacman_install cachyos-kde-settings cachyos-nord-kde-theme-git cachyos-themes-sddm
    fi
    if [[ ${MY_GREETER_AUTOLOGIN:-0} == 1 ]]; then
        chroot_write_file /etc/sddm.conf.d/autologin.conf <<EOF
[Autologin]
User=$MY_USERNAME
Session=plasma
EOF
    fi
    chroot_enable sddm.service polkit.service
}
