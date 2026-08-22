#!/usr/bin/env bash
# modules/zfs.sh — OpenZFS(可选,不进任何 profile)
# 用法:--extra-modules zfs(或设备文件 EXTRA_MODULES 里加)。无 MY_* 开关:
# 模块被解析到即安装,与 docker 等系统模块一致。
# 范围:只提供"能用 zfs"(内核模块 + 用户态工具 + 开机导入/挂载服务)。
# 本安装器根文件系统固定 btrfs(lib/disk.sh 布局),不支持 root on zfs;
# zpool 作为数据盘由首启后的服务自动导入(/etc/zfs/zpool.cache 存在时——
# zfs-import-cache 带 ConditionFileNotEmpty 守卫,空系统上两服务均静默跳过,
# 不产生 failed unit)。池的创建/import 在目标机首启后自行进行。
#
# 包来源按 distro 分支(硬约定:装包/配置/enable 同一模块文件内):
#   cachyos:[cachyos*] 仓库自带按内核变体预编译、依赖锁内核精确版本的
#           ${KERNEL_PKG}-zfs(如 linux-cachyos-server-zfs Depends:
#           linux-cachyos-server=<ver>),与内核同一笔事务解析不会错位;
#           无需额外仓库。注意该包不拉 zfs-utils,必须显式同装
#   arch:  [archzfs] 仓库。官方已从 archzfs.com(停更)迁到 GitHub Releases
#           分发,签名 key 随迁移轮换为 3A9917BF...(再轮换时报 invalid or
#           corrupted package,按 https://github.com/archzfs/archzfs/releases
#           说明更新此 ID)。预编译 zfs-linux 同样锁 linux=<精确 pkgrel>,
#           若上游落后于刚发布的 core/linux 会报无法满足依赖:等其重建后重跑
#
# 版本错位防护:第三方源里 zfs-utils 可能比内核模块包新([archlinuxcn] 的
# zfs-utils 2.4.4 > cachyos/archzfs 的 2.4.3,而 pacman 默认按版本取最高),
# 用户态与内核模块 minor 错位会在每次 import 时报 version skew 警告——故全部
# 用 <repo>/<pkg> 限定名钉死来源,保证用户态与模块同源

mod_install() {
    local pkgs=()
    case $DISTRO in
        cachyos)
            # KERNEL_PKG 由主流程 distro_kernel_packages 在模块循环前设好(全局,
            # 见 arch-install 主入口注释)。[cachyos](基础段)无条件存在于
            # pacman.conf(distro_setup_repos 追加),zfs-utils 从它取
            pkgs+=("${KERNEL_PKG}-zfs" cachyos/zfs-utils)
            ;;
        arch)
            # keyserver 显式指定:chroot 内默认配置可能不可达(cachyos keyring
            # 导入同款做法);--recv-keys 重复导入无害,不做存在性判断
            chroot_run pacman-key --recv-keys 3A9917BF0DED5C13F69AC68FABEC0A1208037BE9 \
                --keyserver keyserver.ubuntu.com
            chroot_run pacman-key --lsign-key 3A9917BF0DED5C13F69AC68FABEC0A1208037BE9
            _zfs_add_archzfs_repo
            # 刷新库索引:刚插入的仓库段不 -Sync 时 pacman 找不到其中 target
            chroot_run pacman -Sy --noconfirm
            pkgs+=(archzfs/zfs-linux archzfs/zfs-utils)
            ;;
        *)
            die "未知 distro: $DISTRO"
            ;;
    esac

    pacman_install "${pkgs[@]}"

    # 根不在 zfs 上,mkinitcpio 无需加 hook/MODULES;数据池靠这两个服务导入挂载。
    # 共享(zfs-share)/zvol(zfs-volume-wait)场景由使用者在 hooks.sh 自行补 enable
    chroot_enable zfs-import-cache.service zfs-mount.service
}

# _zfs_add_archzfs_repo — 往 $MNT_DIR/etc/pacman.conf 插入 [archzfs] 段
# 必须插在 [core] 行之前(unofficial 仓库惯例,优先级高于官方段);
# 用 head/tail 拼接而非 sed r/e:sed 插行会把 [core] 自己的 Include 行挤到段外
# (实测报 no servers configured for repository,distro/cachyos.sh 同款注释)
_zfs_add_archzfs_repo() {
    local conf=$MNT_DIR/etc/pacman.conf
    [[ -f $conf ]] || die "未找到 $conf(distro_setup_repos 应先生成)"
    grep -q '^\[archzfs\]' "$conf" && return 0
    # 先 grep -q 守卫再取行号:set -e+pipefail 下无条件管道遇"无 [core]"会
    # 以非零退出杀脚本(cachyos.sh 同款结构)
    local section
    section=$(printf '[archzfs]\nSigLevel = Required\nServer = %s\n' \
        'https://github.com/archzfs/archzfs/releases/download/experimental')
    if grep -q '^\[core\]' "$conf"; then
        # 必须插在 [core] 行之前(unofficial 仓库惯例,优先级高于官方段);
        # head/tail 拼接而非 sed r/e:sed 插行会把 [core] 自己的 Include 行
        # 挤到段外(实测报 no servers configured,cachyos.sh 同款注释)
        local ln
        ln=$(grep -n '^\[core\]' "$conf" | head -1 | cut -d: -f1)
        { head -n $((ln - 1)) "$conf"; printf '%s' "$section"; tail -n "+$ln" "$conf"; } >"$conf.new"
        mv "$conf.new" "$conf"
    else
        # 无 [core](异常 pacman.conf):追加到尾部保底,别让安装静默走丢
        printf '%s' "$section" >>"$conf"
    fi
}
