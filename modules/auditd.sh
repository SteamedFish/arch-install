#!/usr/bin/env bash
# modules/auditd.sh — 装 audit 包并 enable auditd.service,让 kernel audit
# 事件由 auditd listener 接管,不再走内核 printk fallback
# (详见 audit-in-dmesg.md 2026-07-31 实测)。不写规则、不装 audispd-plugins、不配转发。

mod_install() {
    pacman_install audit
    chroot_enable auditd.service
    # audit.log 高频追加+rotate,与 journal 同理:btrfs 根时禁 COW 防碎片化
    btrfs_nocow_dir /var/log/audit
}