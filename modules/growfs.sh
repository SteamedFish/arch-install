#!/usr/bin/env bash
# modules/growfs.sh — 首启自动扩容根分区(需求 8)
# 原理:systemd-repart 读取 /etc/repart.d/*.conf,Type=linux-root 与本机
# GPT 分区类型(4F68BCE3-... Linux root x86-64)匹配,首启自动扩分区 +
# GrowFileSystem=yes 触发 btrfs 在线扩容。幂等:后续启动发现已是最大则跳过。

mod_install() {
    log "写入 systemd-repart 扩容配置"
    chroot_write_file /etc/repart.d/50-root.conf <<'EOF'
[Partition]
Type=linux-root
GrowFileSystem=yes
EOF
}
