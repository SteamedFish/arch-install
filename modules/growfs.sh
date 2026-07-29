#!/usr/bin/env bash
# modules/growfs.sh — 首启自动扩容根分区(需求 8)
# 原理:systemd-repart 读取 /etc/repart.d/*.conf,Type=root 是本架构 DPS 根分区
# (4F68BCE3-... Linux root x86-64)的别名,与本机 p3 分区类型 GUID 匹配,
# 首启自动扩分区 + GrowFileSystem=yes 触发 btrfs 在线扩容。幂等:已是最大则跳过。
# 注意 1:Type 只能用 DPS 名称(root/root-x86-64 等)——写成 linux-root 会被拒
# ("Failed to parse partition type",qemu 实测)。
# 注意 2:无需装额外包——systemd-repart.service 由 systemd
# 包静态启用(sysinit.target.wants,已实测 is-enabled=static)。
# 注意 3:repart 只扩分区、不扩 btrfs 文件系统(hx370 真机实测:首启日志
# 有 "Growing existing partition"/"Partition table written" 但无 fs grow 行,
# 第二启分区 930G/fs 75G 时报 "No changes"——它不把"分区>fs"视为待办)。
# fs 扩容不走本模块:lib/disk.sh 挂载根分区时带 x-systemd.growfs,
# genfstab 记录后由 fstab-generator 自动生成 systemd-growfs@-.service 处理。

mod_install() {
    log "写入 systemd-repart 扩容配置"
    chroot_write_file /etc/repart.d/50-root.conf <<'EOF'
[Partition]
Type=root
GrowFileSystem=yes
EOF
}
