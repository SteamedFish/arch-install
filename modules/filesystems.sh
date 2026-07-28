#!/usr/bin/env bash
# modules/filesystems.sh — 各类文件系统工具
# btrfs-progs:目标系统内也需要(挂载/维护);cloud-guest-utils 提供 growpart(repart 的备用手段)

mod_install() {
    pacman_install btrfs-progs xfsprogs ntfs-3g exfatprogs dosfstools \
        sshfs nfs-utils parted cloud-guest-utils
}
