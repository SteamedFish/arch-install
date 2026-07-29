#!/usr/bin/env bash
# distro/cachyos.sh — CachyOS 实现
# 两阶段:阶段一由主流程用 distro_base_packages() pacstrap(与 Arch 相同);
# 阶段二在 chroot 内由本文件的 distro_setup_repos() 装 keyring(+可选 mirrorlist)
# 并插入 [cachyos-*] 仓库段,再由 distro_kernel_packages() 装 CachyOS 内核。
# 注意:阶段一 pacstrap 不启用 cachyos 仓库(keyring 未装无法验签),
#       base 系统来自 Arch 仓库,不影响最终系统(阶段二 -Syu 会替换为优化构建)。

# CDN 基址:中国大陆直连 cdn77 可能被重置,用 MY_CACHYOS_CDN 覆盖(如 USTC)
CACHYOS_CDN=${MY_CACHYOS_CDN:-https://cdn77.cachyos.org/repo/x86_64/cachyos}

# 阶段一 base 包与 Arch 相同(主入口只 source 本文件,必须在此重复定义,
# 否则 pacstrap 静默退化为只装 base 元包,缺 linux-firmware 等)
distro_base_packages() {
    # btrfs-progs 必须随 pacstrap 进:内核安装触发 mkinitcpio 时若缺 btrfsck,
    # fsck hook 报 No fsck helpers found 并使 pacman 以"构建有错"退出(实测)
    echo "base linux-firmware efifs iptables-nft btrfs-progs"
}

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
    # 注意不能用 pacman_install(它固定注入 -S,与 -U 冲突);
    # pacman 的 PGP import 询问读 /dev/tty,--noconfirm 与管道均无效(实测),
    # 必须先显式导入并本地签名 CachyOS 打包钥匙。若将来 CachyOS 轮换签名钥,
    # 这里会以新的 key id 报 invalid or corrupted package,届时更新此 ID
    chroot_run pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com
    chroot_run pacman-key --lsign-key F3B607488DB35A47
    chroot_run pacman -U --noconfirm "$(_cachyos_latest_pkg_url cachyos-keyring)"

    # mirrorlist 包只提供默认镜像列表;MY_CACHYOS_MIRRORLIST 指定自有文件时
    # 跳过安装,直接复制该文件并让所有 [cachyos-*] 段引用它
    local cml=/etc/pacman.d/cachyos-mirrorlist
    local ml_level=""
    if [[ -n ${MY_CACHYOS_MIRRORLIST:-} ]]; then
        [[ -f $MY_CACHYOS_MIRRORLIST ]] || die "MY_CACHYOS_MIRRORLIST 不存在: $MY_CACHYOS_MIRRORLIST"
        mkdir -p "$MNT_DIR/etc/pacman.d"
        # 含优化路径的文件必须按段拆成两份:[cachyos] 基础仓库只存在于
        # x86_64/ 目录(实测 x86_64_v4/cachyos 无此库),混放时其 404 会耗尽
        # pacman 对同一 host 的错误预算(too many errors from <host>, skipping),
        # 把同 host 的可用行也一并跳过,-Syy/-S 因此整体失败。
        # 文件不含优化路径(如官方 $arch_v3 单路径写法)则无需拆分
        local archdir=""
        case $CACHYOS_REPO_LEVEL in
            v3) archdir=x86_64_v3 ;;
            # znver4 仓库(cachyos-znver4 等)位于 x86_64_v4/ 路径下、
            # 包 arch 标签也是 x86_64_v4(实测;wiki:znver4 与 v4 共用 mirrorlist)
            v4 | znver4) archdir=x86_64_v4 ;;
        esac
        if [[ -n $archdir ]] && grep -qF "$archdir" "$MY_CACHYOS_MIRRORLIST"; then
            grep -F "$archdir" "$MY_CACHYOS_MIRRORLIST" >"$MNT_DIR/etc/pacman.d/cachyos-mirrorlist-opt"
            grep -v -e x86_64_v3 -e x86_64_v4 -e /znver4/ "$MY_CACHYOS_MIRRORLIST" >"$MNT_DIR/$cml"
            # 文件只含优化路径时,基础段退化为把路径改写成 x86_64(该目录一定存在)
            [[ -s $MNT_DIR/$cml ]] || sed -e 's|x86_64_v[34]|x86_64|g' -e 's|/znver4/|/x86_64/|g' \
                "$MY_CACHYOS_MIRRORLIST" >"$MNT_DIR/$cml"
            ml_level=/etc/pacman.d/cachyos-mirrorlist-opt
        else
            cp "$MY_CACHYOS_MIRRORLIST" "$MNT_DIR/$cml"
            ml_level=$cml
        fi
        log "使用自有 CachyOS mirrorlist: $MY_CACHYOS_MIRRORLIST"
    else
        chroot_run pacman -U --noconfirm "$(_cachyos_latest_pkg_url cachyos-mirrorlist)"
        case $CACHYOS_REPO_LEVEL in
            v3)
                chroot_run pacman -U --noconfirm "$(_cachyos_latest_pkg_url cachyos-v3-mirrorlist)"
                ml_level=/etc/pacman.d/cachyos-v3-mirrorlist ;;
            # znver4 用 v4 mirrorlist(wiki 明示;其仓库在 x86_64_v4/ 路径下)
            v4 | znver4)
                chroot_run pacman -U --noconfirm "$(_cachyos_latest_pkg_url cachyos-v4-mirrorlist)"
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

    # 让 pacman 接受 cachyos 优化构建:v3 包 arch 标签是 x86_64_v3、
    # v4/znver4 包是 x86_64_v4;Architecture=auto 只展开成 x86_64,
    # 实测报 does not have a valid architecture。$arch 取首个值,
    # 官方 mirrorlist 的 $arch_v3 展开(x86_64+字面 _v3)不受影响。
    # 注意 [cachyos] 基础仓库混有 v3 包(如 linux-api-headers),
    # 所以 v4/znver4 也必须同时接受 v3,否则同样报 arch 无效
    local arches=x86_64
    case $CACHYOS_REPO_LEVEL in
        v3) arches="x86_64 x86_64_v3" ;;
        v4 | znver4) arches="x86_64 x86_64_v3 x86_64_v4" ;;
    esac
    sed -i "s/^#\?Architecture = .*/Architecture = $arches/" "$MNT_DIR/etc/pacman.conf"
    # 必须插在 [core] 行之前:sed r/e 是插到该行之后,会让 [core] 丢了自己的
    # Include 行(实测报 no servers configured for repository),故用 head/tail 拼接
    local conf=$MNT_DIR/etc/pacman.conf tmp=$MNT_DIR/tmp/cachyos-repos.conf
    printf '%s' "$sections" >"$tmp"
    if grep -q '^\[core\]' "$conf"; then
        local ln
        ln=$(grep -n '^\[core\]' "$conf" | head -1 | cut -d: -f1)
        { head -n $((ln - 1)) "$conf"; cat "$tmp"; tail -n "+$ln" "$conf"; } >"$conf.new"
        mv "$conf.new" "$conf"
    else
        cat "$tmp" >>"$conf"
    fi
    rm -f "$tmp"

    # 同步新仓库并全量升级(把 Arch 构建替换为 cachyos 优化构建)。
    # pacman_install 固定注入 -S,与 -Syu 叠加报 only one operation,故直写
    chroot_run pacman -Syu --noconfirm
    chroot_run pacman -Sc --noconfirm
}

distro_kernel_packages() {
    local variant=${CACHYOS_KERNEL:-default}
    local kpkg
    case $variant in
        default) kpkg=linux-cachyos ;;
        *) kpkg=linux-cachyos-$variant ;;
    esac
    KERNEL_PKG=$kpkg
    KERNEL_PKGS="$kpkg $kpkg-headers"
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
