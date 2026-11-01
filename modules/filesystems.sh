#!/usr/bin/env bash
# modules/filesystems.sh — 各类文件系统工具
# btrfs-progs:目标系统内也需要(挂载/维护);cloud-guest-utils 提供 growpart(repart 的备用手段)
# btrfs 根另启用月度 scrub(btrfs-scrub@-.timer,btrfs-progs 自带单元)

mod_install() {
    pacman_install btrfs-progs xfsprogs ntfs-3g exfatprogs dosfstools \
        sshfs nfs-utils parted cloud-guest-utils

    # btrfs-scrub@-.timer:每月对根(/ )跑 btrfs scrub,读全盘数据校验 checksum,
    # 有冗余副本(DUP/RAID1)的坏块自动修复,能在 SMART 报错之前发现静默损坏。
    # 单元随 btrfs-progs 装进目标系统:[Timer] OnCalendar=monthly +
    # RandomizedDelaySec=1w(避免同批机器同一天互相抢 IO)+ Persistent=true。
    # Persistent=true 且镜像里没有 stamp 文件 → 首启用首次激活即补跑一次
    # (property 语义:上次触发时间未知时立即触发),正好校验刚 dd 的介质。
    # 非 btrfs 根没有 scrub 语义,跳过。
    local fstype
    fstype=$(root_fstype)
    if [[ $fstype == btrfs ]]; then
        log "btrfs 根:启用 btrfs-scrub@-.timer(每月 scrub)"
        chroot_enable btrfs-scrub@-.timer
    else
        info "根文件系统为 ${fstype:-未知}(非 btrfs),跳过 btrfs-scrub@-.timer"
    fi
}
