#!/usr/bin/env bash
# modules/mem-zram.sh — zram 交换(内存选项 2,与 mem-zswap 互斥)
# zram-generator 读 /etc/systemd/zram-generator.conf,由 systemd 生成器自动
# 实例化 systemd-zram-setup@zram0.service,无需手动 enable 任何服务。

mod_conflicts() { echo mem-zswap; }

mod_install() {
    pacman_install zram-generator
    chroot_write_file /etc/systemd/zram-generator.conf <<'EOF'
[zram0]
zram-size = ram
compression-algorithm = zstd
EOF
}
