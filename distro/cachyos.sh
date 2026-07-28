#!/usr/bin/env bash
# distro/cachyos.sh — CachyOS 实现
# 两阶段:阶段一由主流程用 distro_base_packages() pacstrap(与 Arch 相同);
# 阶段二在 chroot 内由本文件的 distro_setup_repos() 装 keyring(+可选 mirrorlist)
# 并插入 [cachyos-*] 仓库段,再由 distro_kernel_packages() 装 CachyOS 内核。
# 注意:阶段一 pacstrap 不启用 cachyos 仓库(keyring 未装无法验签),
#       base 系统来自 Arch 仓库,不影响最终系统(阶段二 -Syu 会替换为优化构建)。

CACHYOS_CDN="https://cdn77.cachyos.org/repo/x86_64/cachyos"

# 查询 CDN 上某包的最新版本并输出完整 URL(包版本会更新,不能写死)。
# 目录列表中形如 cachyos-keyring-20250601-1-any.pkg.tar.zst(另有 .sig 需排除)。
_cachyos_latest_pkg_url() {
    local name=$1 file
    file=$(curl -fsSL "$CACHYOS_CDN/" 2>/dev/null \
        | grep -oE "${name}-[0-9][^\"'<>]*-any\.pkg\.tar\.zst" \
        | grep -v '\.sig$' | sort -V | tail -1)
    [[ -n $file ]] || die "无法在 $CACHYOS_CDN 找到 $name(网络问题或包已改名)"
    echo "$CACHYOS_CDN/$file"
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
    # znver4 仅 AMD 平台可能;检测基于宿主机 CPU,跨厂商构建(--cputype)
    # 时 gcc -march=native 不可信,请用 --cachyos-repo 显式指定
    local family=${CPUTYPE:-auto}
    [[ $family == auto ]] && family=$(detect_cputype)
    if [[ $family == amd ]]; then
        local march
        march=$(gcc -march=native -Q --help=target 2>/dev/null | grep 'march=' | head -1 | awk '{print $NF}')
        if [[ $march == znver4 ]]; then
            CACHYOS_REPO_LEVEL=znver4
            return
        fi
    fi
    if grep -q x86-64-v4 <<<"$supported"; then
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

    # keyring 必装(仓库验签),版本从 CDN 实时查询
    pacman_install -U "$(_cachyos_latest_pkg_url cachyos-keyring)"

    # mirrorlist 包只提供默认镜像列表;MY_CACHYOS_MIRRORLIST 指定自有文件时
    # 跳过安装,直接复制该文件并让所有 [cachyos-*] 段引用它
    local cml=/etc/pacman.d/cachyos-mirrorlist
    local ml_level=""
    if [[ -n ${MY_CACHYOS_MIRRORLIST:-} ]]; then
        [[ -f $MY_CACHYOS_MIRRORLIST ]] || die "MY_CACHYOS_MIRRORLIST 不存在: $MY_CACHYOS_MIRRORLIST"
        mkdir -p "$MNT_DIR/etc/pacman.d"
        cp "$MY_CACHYOS_MIRRORLIST" "$MNT_DIR/$cml"
        ml_level=$cml
        log "使用自有 CachyOS mirrorlist: $MY_CACHYOS_MIRRORLIST"
    else
        pacman_install -U "$(_cachyos_latest_pkg_url cachyos-mirrorlist)"
        case $CACHYOS_REPO_LEVEL in
            v3 | znver4)
                pacman_install -U "$(_cachyos_latest_pkg_url cachyos-v3-mirrorlist)"
                ml_level=/etc/pacman.d/cachyos-v3-mirrorlist ;;
            v4)
                pacman_install -U "$(_cachyos_latest_pkg_url cachyos-v4-mirrorlist)"
                ml_level=/etc/pacman.d/cachyos-v4-mirrorlist ;;
        esac
    fi

    # 生成 cachyos 仓库段,必须插在 [core] 之前(cachyos 包优先级更高)
    local sections=""
    if [[ -n $ml_level ]]; then
        local suffix=$CACHYOS_REPO_LEVEL
        sections="[cachyos-$suffix]
Include = $ml_level
[cachyos-core-$suffix]
Include = $ml_level
[cachyos-extra-$suffix]
Include = $ml_level
"
    fi
    sections+="[cachyos]
Include = $cml
"

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
