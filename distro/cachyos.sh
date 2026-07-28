#!/usr/bin/env bash
# distro/cachyos.sh — CachyOS 实现
# 两阶段:阶段一由主流程用 distro_base_packages() pacstrap(与 Arch 相同);
# 阶段二在 chroot 内由本文件的 distro_setup_repos() 装 keyring/mirrorlist 并插入
# [cachyos-*] 仓库段,再由 distro_kernel_packages() 装 CachyOS 内核与 settings。
# 注意:阶段一 pacstrap 不启用 cachyos 仓库(keyring 未装无法验签),
#       base 系统来自 Arch 仓库,不影响最终系统(阶段二 -Syu 会替换为优化构建)。

CACHYOS_KEYRING_URL="https://cdn77.cachyos.org/repo/x86_64/cachyos/cachyos-keyring-20240331-1-any.pkg.tar.zst"
CACHYOS_MIRRORLIST_URL="https://cdn77.cachyos.org/repo/x86_64/cachyos/cachyos-mirrorlist-22-1-any.pkg.tar.zst"
CACHYOS_V3_MIRRORLIST_URL="https://cdn77.cachyos.org/repo/x86_64/cachyos/cachyos-v3-mirrorlist-22-1-any.pkg.tar.zst"
CACHYOS_V4_MIRRORLIST_URL="https://cdn77.cachyos.org/repo/x86_64/cachyos/cachyos-v4-mirrorlist-22-1-any.pkg.tar.zst"

distro_base_packages() {
    echo "base linux-firmware efifs iptables-nft"
}

# 输出 v3|v4|znver4|generic(写入全局 CACHYOS_REPO_LEVEL)
_cachyos_detect_level() {
    # --cachyos-repo 显式指定优先
    if [[ -n ${CACHYOS_REPO:-} && ${CACHYOS_REPO:-} != auto ]]; then
        CACHYOS_REPO_LEVEL=$CACHYOS_REPO
        return
    fi
    local supported
    supported=$(/lib/ld-linux-x86-64.so.2 --help 2>/dev/null | grep -o 'x86-64-v[34]' | sort -u)
    local march
    march=$(gcc -march=native -Q --help=target 2>/dev/null | grep 'march=' | head -1 | awk '{print $NF}')
    if [[ $march == znver4 ]]; then
        CACHYOS_REPO_LEVEL=znver4
    elif grep -q x86-64-v4 <<<"$supported"; then
        CACHYOS_REPO_LEVEL=v4
    elif grep -q x86-64-v3 <<<"$supported"; then
        CACHYOS_REPO_LEVEL=v3
    else
        CACHYOS_REPO_LEVEL=generic
    fi
}

distro_setup_repos() {
    _cachyos_detect_level
    log "CachyOS 仓库优化等级: $CACHYOS_REPO_LEVEL"

    # keyring + mirrorlist(从 URL 装,此时目标系统还没有 cachyos 仓库)
    pacman_install -U "$CACHYOS_KEYRING_URL" "$CACHYOS_MIRRORLIST_URL"
    local level_pkgs=()
    case $CACHYOS_REPO_LEVEL in
        v3 | znver4) level_pkgs=("$CACHYOS_V3_MIRRORLIST_URL") ;;
        v4) level_pkgs=("$CACHYOS_V4_MIRRORLIST_URL") ;;
    esac
    ((${#level_pkgs[@]})) && pacman_install -U "${level_pkgs[@]}"

    # 生成 cachyos 仓库段,必须插在 [core] 之前(cachyos 包优先级更高)
    local sections=""
    case $CACHYOS_REPO_LEVEL in
        v3)
            sections='[cachyos-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist
[cachyos-core-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist
[cachyos-extra-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist
'
            ;;
        v4)
            sections='[cachyos-v4]
Include = /etc/pacman.d/cachyos-v4-mirrorlist
[cachyos-core-v4]
Include = /etc/pacman.d/cachyos-v4-mirrorlist
[cachyos-extra-v4]
Include = /etc/pacman.d/cachyos-v4-mirrorlist
'
            ;;
        znver4)
            sections='[cachyos-znver4]
Include = /etc/pacman.d/cachyos-v3-mirrorlist
[cachyos-core-znver4]
Include = /etc/pacman.d/cachyos-v3-mirrorlist
[cachyos-extra-znver4]
Include = /etc/pacman.d/cachyos-v3-mirrorlist
'
            ;;
    esac
    sections+='[cachyos]
Include = /etc/pacman.d/cachyos-mirrorlist
'

    # Architecture=auto 让 pacman 识别 x86_64_v3 等包
    chroot_run sed -i 's/^#Architecture = auto/Architecture = auto/' /etc/pacman.conf
    # 插在 [core] 前;若无 [core](异常)则追加到末尾
    printf '%s' "$sections" >"$MNT_DIR/tmp/cachyos-repos.conf"
    if grep -q '^\[core\]' "$MNT_DIR/etc/pacman.conf"; then
        chroot_run sed -i '/^\[core\]/e cat /tmp/cachyos-repos.conf' /etc/pacman.conf
    else
        cat "$MNT_DIR/tmp/cachyos-repos.conf" >>"$MNT_DIR/etc/pacman.conf"
    fi
    rm -f "$MNT_DIR/tmp/cachyos-repos.conf"

    # 同步新仓库并全量升级(把 Arch 构建替换为 cachyos 优化构建)
    pacman_install -Syu
}

distro_kernel_packages() {
    local variant=${CACHYOS_KERNEL:-default}
    local kpkg
    case $variant in
        default) kpkg=linux-cachyos ;;
        *) kpkg=linux-cachyos-$variant ;;
    esac
    KERNEL_PKG=$kpkg
    echo "$kpkg $kpkg-headers"
}

distro_post_install() {
    # cachyos-settings:zram/ananicy/thp 等系统调优(会拉 zram-generator、ananicy-cpp 等依赖)
    pacman_install cachyos-settings
    # --mirrorlist reflector 时用 cachyos 官方排序工具重排(需要联网)
    if [[ ${MIRRORLIST:-copy} == reflector ]]; then
        pacman_install cachyos-rate-mirrors
        chroot_run cachyos-rate-mirrors || warn "cachyos-rate-mirrors 失败(可能无网络),保持默认顺序"
    fi
}
