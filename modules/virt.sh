#!/usr/bin/env bash
# modules/virt.sh — qemu/libvirt 虚拟化工具(可选,不在默认 profile)
# 读取变量:MY_USERNAME(加入 libvirt 组)

mod_install() {
    pacman_install qemu-base qemu-img libvirt virt-install dnsmasq
    chroot_enable libvirtd.socket
    chroot_run usermod -aG libvirt "$MY_USERNAME"
}
