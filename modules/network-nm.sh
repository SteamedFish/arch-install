#!/usr/bin/env bash
# modules/network-nm.sh — NetworkManager(桌面用;server/VPS 用 network-networkd)
# enable 服务:NetworkManager.service;显式 disable networkd 防止两者并存(用户踩过的坑)

mod_install() {
    pacman_install networkmanager
    chroot_enable NetworkManager.service
    chroot_run systemctl disable systemd-networkd.service 2>/dev/null || true
}

mod_conflicts() { echo network-networkd; }
