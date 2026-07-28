#!/usr/bin/env bash
# modules/security.sh — sudo 配置、subuid/subgid(rootless 容器前提)
# 读取变量:MY_USERNAME

mod_install() {
    pacman_install sudo
    chroot_write_file /etc/sudoers.d/myconf <<'EOF'
## wheel 组免密 sudo(个人机器,按需收紧)
%wheel ALL=(ALL:ALL) NOPASSWD: ALL
%sudo   ALL=(ALL:ALL) ALL
EOF
    chmod 440 "${MNT_DIR}/etc/sudoers.d/myconf"

    # rootless docker/podman 需要 subuid/subgid 映射
    chroot_write_file /etc/subuid <<<"${MY_USERNAME}:231072:65536"
    chroot_write_file /etc/subgid <<<"${MY_USERNAME}:231072:65536"
}
