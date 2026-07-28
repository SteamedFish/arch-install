#!/usr/bin/env bash
# modules/bluetooth.sh — 蓝牙(可选)
# enable 服务:bluetooth.service

mod_install() {
    pacman_install bluez bluez-utils
    chroot_enable bluetooth.service
}
