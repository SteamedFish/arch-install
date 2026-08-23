#!/usr/bin/env bash
# modules/mem-zswap.sh — zswap(内存选项 3,默认,与 mem-zram 互斥)
# zswap 参数配置:内建内核参数无 sysctl/modprobe.d 机制(modprobe options
# 只作用于动态加载的模块,已查 modprobe.d(5) 验证),tmpfiles.d 是 Arch Wiki
# 推荐的正统写法——systemd-tmpfiles-setup.service 启动早期静态运行,先于
# 任何 swap 使用。
# zswap 只是 swap 前的压缩缓存,本身不是 swap 设备,必须配后备 swap 才生效
# → 本模块同时创建 btrfs NOCOW swapfile(独立嵌套 subvol,快照不会包含)。
# 读取变量:MY_SWAP_SIZE(默认 4G;"0"=不建 swapfile,退回 zram)

mod_requires() { echo filesystems; }
mod_conflicts() { echo mem-zram; }

mod_install() {
    # w <路径> <mode> <uid> <gid> <age> <写入值>
    chroot_write_file /etc/tmpfiles.d/zswap.conf <<'EOF'
w /sys/module/zswap/parameters/enabled - - - - 1
w /sys/module/zswap/parameters/compressor - - - - zstd
w /sys/module/zswap/parameters/max_pool_percent - - - - 20
w /sys/module/zswap/parameters/zpool - - - - zsmalloc
EOF

    # zswap 按页压缩缓存,swap 预读(page-cluster>0)会把相邻未命中页整批
    # 换入,徒增解压开销且稀释缓存命中,内核文档/Arch Wiki 对 zswap 场景
    # 推荐 0。仅写在真实启用 zswap 的路径;MY_SWAP_SIZE=0 回退 zram 分支
    # 不写(zram 同样受益于 0,需要时再补进 mem-zram)。
    chroot_write_file /etc/sysctl.d/70-zswap.conf <<'EOF'
# 由 mem-zswap 写入:zswap 已启用,关闭 swap 预读
vm.page-cluster = 0
EOF

    local size=${MY_SWAP_SIZE:-4G}
    if [[ $size == 0 ]]; then
        # 无后备 swap 设备时 zswap 永不生效 → 按约定退回 zram(自带 swap 设备)
        log "MY_SWAP_SIZE=0,改用 zram"
        pacman_install zram-generator
        chroot_write_file /etc/systemd/zram-generator.conf <<'EOF'
[zram0]
zram-size = ram
compression-algorithm = zstd
EOF
        # 纯 zram 同款配套,内容与 mem-zram 一致(两分支本就重复
        # zram-generator.conf,保持平齐):关 zswap(出厂默认开,双重压缩链)
        # + swap 调优五键。理由详见 modules/mem-zram.sh。
        chroot_write_file /etc/tmpfiles.d/zswap-off.conf <<'EOF'
w /sys/module/zswap/parameters/enabled - - - - 0
EOF
        chroot_write_file /etc/sysctl.d/70-zram.conf <<'EOF'
# 由 mem-zswap 回退 zram 分支写入:纯 zram 场景优化
vm.swappiness = 180
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
vm.page-cluster = 0
vm.vfs_cache_pressure = 50
EOF
        return 0
    fi
    log "创建 btrfs swapfile($size)"
    btrfs subvolume create "${MNT_DIR}/swap"
    # btrfs filesystem mkswapfile 自带 NOCOW/预分配/mkswap 全套校验(btrfs-progs ≥ 6.1)
    btrfs filesystem mkswapfile --size "$size" "${MNT_DIR}/swap/swapfile"
    echo '/swap/swapfile none swap defaults 0 0' >>"${MNT_DIR}/etc/fstab"

    # 禁掉 zram-generator 默认设备:cachyos-settings 依赖 zram-generator 且自带
    # /usr/lib/systemd/zram-generator.conf(zram-size=ram,会吃掉全部内存,
    # 与本模块 swapfile+zswap 设计冲突)。/etc 同名文件优先于 /usr/lib,
    # 无任何 [zramN] 段 = 不创建任何设备(实测生成器对空配置不建设备)。
    # 注意必须只在 swapfile 路径写:上面的 MY_SWAP_SIZE=0 分支故意用 zram。
    chroot_write_file /etc/systemd/zram-generator.conf <<'EOF'
# 由 mem-zswap 模块写入:本机使用 swapfile+zswap,不创建 zram 设备
EOF
}
