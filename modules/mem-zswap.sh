#!/usr/bin/env bash
# modules/mem-zswap.sh — zswap(内存选项 3,默认,与 mem-zram 互斥)
# zswap 参数配置:内建内核参数无 sysctl/modprobe.d 机制(modprobe options
# 只作用于动态加载的模块,已查 modprobe.d(5) 验证),tmpfiles.d 是 Arch Wiki
# 推荐的正统写法——systemd-tmpfiles-setup.service 启动早期静态运行,先于
# 任何 swap 使用。
# zswap 只是 swap 前的压缩缓存,本身不是 swap 设备,必须配后备 swap 才生效
# → 本模块同时创建 btrfs NOCOW swapfile(独立嵌套 subvol,快照不会包含)。
# 读取变量:MY_SWAP_SIZE(默认 4G;"0"=不建 swapfile,仅写 zswap 参数)

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

    local size=${MY_SWAP_SIZE:-4G}
    [[ $size == 0 ]] && { log "MY_SWAP_SIZE=0,跳过 swapfile"; return 0; }
    log "创建 btrfs swapfile($size)"
    btrfs subvolume create "${MNT_DIR}/swap"
    # btrfs filesystem mkswapfile 自带 NOCOW/预分配/mkswap 全套校验(btrfs-progs ≥ 6.1)
    btrfs filesystem mkswapfile --size "$size" "${MNT_DIR}/swap/swapfile"
    echo '/swap/swapfile none swap defaults 0 0' >>"${MNT_DIR}/etc/fstab"
}
