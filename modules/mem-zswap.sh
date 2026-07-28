#!/usr/bin/env bash
# modules/mem-zswap.sh — zswap(内存选项 3,默认,与 mem-zram 互斥)
# zswap 没有原生配置文件机制,但可用 tmpfiles.d 在启动早期(systemd-tmpfiles-
# setup.service,静态启用,先于 swap 使用)写 sysfs 参数 —— 纯配置文件方案,
# 无需自写 service。备选方案是内核启动参数(zswap.compressor=zstd 等),
# 见 loader entries,此处不采用以保持引导项与发行版无关。
# 注意:zswap 只是 swap 前的压缩缓存,本身不是 swap 设备;没有任何后备
# swap(分区/文件)时 zswap 不会触发。如需后备,见 mem-zram 或自行加 swapfile。

mod_conflicts() { echo mem-zram; }

mod_install() {
    # w <路径> <mode> <uid> <gid> <age> <写入值>
    chroot_write_file /etc/tmpfiles.d/zswap.conf <<'EOF'
w /sys/module/zswap/parameters/enabled - - - - 1
w /sys/module/zswap/parameters/compressor - - - - zstd
w /sys/module/zswap/parameters/max_pool_percent - - - - 20
w /sys/module/zswap/parameters/zpool - - - - zsmalloc
EOF
}
