#!/usr/bin/env bash
# modules/desktop-niri.sh — niri(Wayland 滚动平铺合成器)+ uwsm + DMS 全家
# 依赖(由 resolver 闭包自动补):audio fonts ime network-nm
# 读取变量:MY_GREETER_AUTOLOGIN(1=autologin,仅家中台式机;笔记本必须 0)、MY_USERNAME
# enable 服务:greetd.service;--global:dbus-broker.service
# 用户态(dms.service、环境变量、spawn-at-startup)归 dotfiles,不在此处理

mod_requires() { echo audio fonts ime network-nm; }
mod_conflicts() { echo desktop-kde; }

mod_install() {
    local -a pkgs=(niri uwsm libnewt xwayland-satellite \
        xdg-desktop-portal-gnome xdg-desktop-portal-gtk gnome-keyring \
        dbus-broker \
        greetd greetd-tuigreet \
        polkit polkit-kde-agent \
        dms-shell dms-shell-niri quickshell \
         kitty alacritty fuzzel mako waybar swaybg swayidle \
         xclip wl-clipboard \
         awww udiskie brightnessctl \
        matugen cava qt6-multimedia-ffmpeg)
    # dms-shell 推荐依赖(matugen 动态配色/cava 音频可视化/qt6 多媒体),
    # 与 dms 同处安装避免后续补装时的顺序问题
    if [[ ${DISTRO:-arch} != cachyos ]]; then
        pkgs+=(swaylock)
    fi
    # CachyOS 不装原生 swaylock:cachyos-niri-settings 硬依赖
    # swaylock-effects-git(provides/conflicts swaylock),与原生包互斥;
    # 锁屏由该包的 swaylock-effects-git 提供(niri 的 swaylock optdep 命中虚拟提供)

    pacman_install "${pkgs[@]}"

    # CachyOS 专有:niri 设置包(仅 [cachyos] 库有)
    if [[ ${DISTRO:-arch} == cachyos ]]; then
        pacman_install cachyos-niri-settings
    fi

    # dbus-broker 取代 dbus-daemon(uwsm/portal 栈推荐)
    chroot_run systemctl --global enable dbus-broker.service

    # greeter:greetd + tuigreet,经 uwsm 启动 niri
    chroot_write_file /etc/greetd/config.toml <<EOF
[terminal]
vt = 1

[default_session]
command = "tuigreet --time --remember --cmd 'uwsm start niri.desktop'"
user = "greeter"
EOF
    if [[ ${MY_GREETER_AUTOLOGIN:-0} == 1 ]]; then
        cat >>"${MNT_DIR}/etc/greetd/config.toml" <<EOF

[initial_session]
command = "uwsm start niri.desktop"
user = "$MY_USERNAME"
EOF
    fi
    chroot_enable greetd.service
}
