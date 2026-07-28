#!/usr/bin/env bash
# modules/ssh.sh — openssh 服务
# 读取变量:MY_SSH_PORT(空则 22)
# enable 服务:sshd.service

mod_install() {
    local port=${MY_SSH_PORT:-22}
    pacman_install openssh
    chroot_write_file /etc/ssh/sshd_config.d/99-my.conf <<EOF
Port $port
PermitRootLogin no
PasswordAuthentication no
EOF
    chroot_enable sshd.service
}
