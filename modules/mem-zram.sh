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

    # 纯 zram 必须关掉 zswap:Arch 出厂 CONFIG_ZSWAP_DEFAULT_ON=y(config.x86_64
    # 实拉核实),zswap 会把换出页先压进自己的池、池满才写到后端(zram),形成
    # 双重压缩链白费 CPU,Arch Wiki Zram 页明确要求纯 zram 场景禁用。内建参数
    # 只能走 tmpfiles.d(与 mem-zswap 的 enabled=1 同款手法),两模块互斥保证
    # zswap.conf/zswap-off.conf 不会同时存在。
    chroot_write_file /etc/tmpfiles.d/zswap-off.conf <<'EOF'
w /sys/module/zswap/parameters/enabled - - - - 0
EOF

    # Arch Wiki "Optimizing swap on zram"(Pop!_OS/r/Fedora 基准同值):
    # swappiness=180——内核文档对内存型 swap 建议超 100,zram 随机 IO 比盘快
    # 数量级;page-cluster=0——RAM 设备预读无意义;watermark_boost_factor=0
    # 关掉分配尖峰后的 kswapd 过度回收抖动、watermark_scale_factor=125 让
    # kswapd 更早平缓启动;vfs_cache_pressure=50 压力由压缩 swap 兜底多留
    # dentries/inodes(CachyOS cachyos-settings 同值)。CachyOS 分支与
    # cachyos-settings 并存时本文件词序在后、重复键以这里为准。
    chroot_write_file /etc/sysctl.d/70-zram.conf <<'EOF'
# 由 mem-zram 写入:纯 zram 场景优化
vm.swappiness = 180
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
vm.page-cluster = 0
vm.vfs_cache_pressure = 50
EOF
}
