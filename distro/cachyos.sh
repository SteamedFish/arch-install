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
    # iptables-nft 仅为 docker 保留(运行时调 iptables 命令建 NAT 链;移除会让后装
    # docker 时 pacman 按字母序挑 provider)。防火墙本体已迁 nftables(modules/firewall.sh)
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

# 宿主 CPU 执行能力等级:输出 generic|v3|v4(znver4 归并为 v4,仅用于比较)。
# 纯宿主信号,与目标机 CPUTYPE 无关:gcc -march=native 永远探测的是构建机 CPU。
# ld.so 判定必须带 "(supported":不支持的级别也输出裸级别名,只判字符串存在
# 会把 v3-only 宿主误判成 v4(2700X 上 -Syu 拉入 v4 二进制即 Illegal instruction)
_cachyos_host_level() {
    local supported march
    supported=$(/lib/ld-linux-x86-64.so.2 --help 2>/dev/null)
    march=$(gcc -march=native -Q --help=target 2>/dev/null | awk '/^march=/{print $NF; exit}')
    if [[ $march == znver4 || $march == znver5 ]] || grep -q 'x86-64-v4 (supported' <<<"$supported"; then
        echo v4
    elif grep -q 'x86-64-v3 (supported' <<<"$supported"; then
        echo v3
    else
        echo generic
    fi
}

_cachyos_level_rank() {
    case $1 in
        generic) echo 0 ;;
        v3) echo 1 ;;
        v4 | znver4) echo 2 ;;
        *) die "未知 CachyOS 仓库等级: $1" ;;
    esac
}

# 跨等级构建预检:显式 --cachyos-repo 高于宿主能力时直接拒绝(动磁盘前)。
# 为什么不能模拟:x86-64-v4/znver4 包含 AVX-512,而 qemu TCG(用户态与系统
# 模式同源)至今未实现 AVX-512(qemu#2878),v4 二进制在任何模拟路径下都会
# SIGILL——宿主实测 qemu 11.1 复现。出路:换 v4 级构建机,或降目标等级。
_cachyos_preflight_emulation() {
    HOST_LEVEL=$(_cachyos_host_level)
    if [[ ${CACHYOS_REPO:-} == auto || -z ${CACHYOS_REPO:-} ]]; then
        return 0   # auto 跟随宿主能力,原生执行
    fi
    if (($( _cachyos_level_rank "$CACHYOS_REPO") <= $( _cachyos_level_rank "$HOST_LEVEL"))); then
        return 0   # 显式等级不超过宿主能力,原生执行
    fi
    die "仓库优化等级 $CACHYOS_REPO 高于宿主执行能力($HOST_LEVEL):v4 含 AVX-512,
qemu TCG 不支持模拟该指令集(qemu#2878),chroot 内必 SIGILL。请在 v4 级构建机上运行,
或改用 --cachyos-repo $HOST_LEVEL。"
}

# 输出 v3|v4|znver4|generic(写入全局 CACHYOS_REPO_LEVEL)
_cachyos_detect_level() {
    # --cachyos-repo 显式指定优先;高于宿主的等级已被预检拒绝,此处必可原生执行
    if [[ -n ${CACHYOS_REPO:-} && ${CACHYOS_REPO:-} != auto ]]; then
        CACHYOS_REPO_LEVEL=$CACHYOS_REPO
    else
        CACHYOS_REPO_LEVEL=${HOST_LEVEL:-$(_cachyos_host_level)}
    fi
}

distro_setup_repos() {
    # 启用 multilib(wine/steam 等 32 位依赖;与 arch.sh 同款,与 cachyos 仓库
    # 配置顺序无关——[multilib] 在 [core] 之后,后置插入不会影响)。此处无条件
    # 启用,不依赖 pacman 模块是否加载。原 pacman 模块里的同名 sed 已下放。
    sed -i '/^#\[multilib\]/ { s/^#//; n; /^#Include/ s/^#// }' "$MNT_DIR/etc/pacman.conf"

    _cachyos_detect_level
    log "CachyOS 仓库优化等级: $CACHYOS_REPO_LEVEL(宿主能力: ${HOST_LEVEL:-?})"

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
    # cachyos-settings:zram/ananicy/thp 等系统调优(会拉 zram-generator、ananicy-cpp 等依赖;
    # 其 zram 默认配置由 mem-zswap 模块在 swapfile 路径下用 /etc 覆盖文件禁用)
    # cachyos-hooks:alpm hooks(branding/os-release/update-initramfs 等)——注意它不含
    # mkinitcpio preset,fallback initramfs 仍不会生成(install_bootloader 已按存在性跳过)
    # cachyos-zsh-config:官方安装器对用户 shell 的同款处理(base.sh 固定 zsh)
    # 注:曾考虑加 systemd-boot-manager(AUR)自动维护 loader entries,但它假定
    # ${ESP}/vmlinuz-* + ${ESP}/loader/entries/ 的合并布局;本项目 /efi(纯 ESP)+
    # /boot(XBOOTLDR)双区,内核与 entries 在 /boot,不在 /efi,故不兼容
    pacman_install cachyos-settings cachyos-hooks cachyos-zsh-config
    # --mirrorlist reflector 时用 cachyos 官方排序工具重排(需要联网)
    if [[ ${MIRRORLIST:-copy} == reflector ]]; then
        pacman_install cachyos-rate-mirrors
        chroot_run cachyos-rate-mirrors || warn "cachyos-rate-mirrors 失败(可能无网络),保持默认顺序"
    fi
}
