#!/usr/bin/env bash
# tests/run.sh — 纯 bash 自测(无外部依赖):bash tests/run.sh
set -uo pipefail
cd "$(dirname "$0")/.."

PASS=0 FAIL=0
ok()   { PASS=$((PASS+1)); printf 'ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf 'FAIL %s\n' "$1"; }
check(){ if eval "$2" &>/dev/null; then ok "$1"; else bad "$1"; fi; }

# ---- 1. 所有 bash 文件语法检查 ----
while IFS= read -r f; do
    check "bash -n $f" "bash -n '$f'"
done < <(find arch-install lib distro modules profiles config tests -type f \( -name '*.sh' -o -name 'arch-install' -o -name '*.conf' \) | sort)

# ---- 2. 模块元数据契约 ----
for m in modules/*.sh; do
    name=$(basename "$m" .sh)
    check "$name 定义 mod_install" "grep -q '^mod_install()' '$m'"
    # requires/conflicts/before 引用的模块必须存在(desktop-kde/niri 等真实模块)
    for fn in mod_requires mod_conflicts mod_before; do
        if grep -q "^$fn()" "$m"; then
            deps=$(bash -c "source '$m'; $fn" 2>/dev/null)
            for d in $deps; do
                check "$name.$fn 引用的 $d 存在" "[[ -f 'modules/$d.sh' ]]"
            done
        fi
    done
done

# ---- 3. profile 引用的模块必须存在(desktop 占位符除外)----
for p in profiles/*.conf; do
    while read -r line; do
        [[ $line =~ ^[a-z-]+$ ]] || continue
        [[ $line == desktop ]] && continue
        check "$p 引用的 $line 存在" "[[ -f 'modules/$line.sh' ]]"
    done < <(grep -v '^\s*#' "$p")
done

# ---- 4. 硬约定:模块内不得硬编码个人信息(检查原脚本里的具体个人值)----
check "无硬编码用户名 steamedfish" "! grep -rn 'steamedfish' modules/ distro/ lib/ arch-install profiles/ | grep -v '^Binary'"
check "无硬编码个人 IP(192.168.1.1/192.168.82.66)" "! grep -rn '192\.168\.1\.1\|192\.168\.82\.66' modules/ distro/ lib/ arch-install profiles/"
check "无硬编码 ssh 端口 32200" "! grep -rn '32200' modules/ distro/ lib/ arch-install profiles/"

# ---- 5. 解析器单测(隔离环境,假模块)----
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/modules" "$TMP/profiles"
cat >"$TMP/modules/a.sh" <<'EOF'
mod_install() { :; }
mod_requires() { echo b; }
EOF
cat >"$TMP/modules/b.sh" <<'EOF'
mod_install() { :; }
EOF
cat >"$TMP/modules/c.sh" <<'EOF'
mod_install() { :; }
mod_before() { echo a; }
mod_conflicts() { echo d; }
EOF
cat >"$TMP/profiles/test.conf" <<'EOF'
MODULES=(a c)
EOF
result=$(
    # shellcheck source=../lib/common.sh
    source lib/common.sh
    SCRIPT_DIR="$TMP"
    DESKTOP=niri EXTRA_MODULES="" SKIP_MODULES="" MY_GPU_MODULES=""
    source lib/modules.sh
    resolve_modules test 2>/dev/null
    echo "${RESOLVED_MODULES[*]}"
)
check "requires 闭包(a→b 自动补全)" "grep -qw b <<<'$result'"
pos_c=$(tr ' ' '\n' <<<"$result" | grep -nx c | cut -d: -f1)
pos_a=$(tr ' ' '\n' <<<"$result" | grep -nx a | cut -d: -f1)
check "mod_before 生效(c 在 a 前)" "[[ -n $pos_c && -n $pos_a && $pos_c -lt $pos_a ]]"

# conflicts 应报错
conflict_err=$(
    source lib/common.sh
    SCRIPT_DIR="$TMP"
    DESKTOP=niri EXTRA_MODULES="d" SKIP_MODULES="" MY_GPU_MODULES=""
    source lib/modules.sh
    mkdir -p "$TMP/modules"; echo 'mod_install() { :; }' >"$TMP/modules/d.sh"
    resolve_modules test 2>&1 >/dev/null || true
)
check "conflicts 检测(c+d 报错)" "grep -q 冲突 <<<'$conflict_err'"

# ---- 6. dry-run(需要临时 config)----
if [[ ! -f config/config.sh ]]; then
    printf 'MY_USERNAME="dryrun-test"\nMY_SSH_PUBKEYS=("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDummyKeyForDryRunOnly dryrun@test")\n' >config/config.sh
    CLEANUP_CONFIG=1
fi
check "dry-run server" "./arch-install --target /tmp/x.img --profile server --dry-run >/dev/null 2>&1"
check "dry-run desktop niri" "./arch-install --target /tmp/x.img --profile desktop --desktop niri --dry-run >/dev/null 2>&1"
check "dry-run cachyos" "./arch-install --target /tmp/x.img --profile server --distro cachyos --cachyos-kernel bore --dry-run >/dev/null 2>&1"
dryrun_out=$(./arch-install --target /tmp/x.img --profile desktop --desktop niri --dry-run 2>/dev/null)
check "dry-run 输出含模块顺序" "grep -q desktop-niri <<<'$dryrun_out'"

# ---- 7. 专项断言 ----
check "debug 模块存在" "[[ -f modules/debug.sh ]]"
check "gaming 含 archlinuxcn 包" "grep -q an-anime-game-launcher-bwrap modules/gaming.sh"
check "cachyos 查询最新版" "grep -q _cachyos_latest_pkg_url distro/cachyos.sh"
check "cachyos 支持自有 mirrorlist" "grep -q MY_CACHYOS_MIRRORLIST distro/cachyos.sh"
check "支持 --cputype" "grep -q -- '--cputype' arch-install"
check "KDE 专属应用在 desktop-kde" "grep -qw dolphin modules/desktop-kde.sh"
# tokodon/neochat 是 KDE 原生但归社交客户端,已在 gui-apps;dolphin/kate 等
# KDE 系统应用仍不应渗入
if grep -qw 'dolphin\|kate' modules/gui-apps.sh; then
    bad "gui-apps 不应含 KDE 系统应用"
else
    ok "gui-apps 无 KDE 系统应用"
fi
check "gui-apps 含 neochat(社交客户端)" "grep -qw neochat modules/gui-apps.sh"
check "gui-apps 含 tokodon(社交客户端)" "grep -qw tokodon modules/gui-apps.sh"
check "desktop-kde 不再含 neochat" "! grep -qw neochat modules/desktop-kde.sh"
check "desktop-kde 不再含 tokodon" "! grep -qw tokodon modules/desktop-kde.sh"
modules_list=$(./arch-install --modules 2>/dev/null)
check "--modules 输出含 desktop-niri" "grep -q desktop-niri <<<'$modules_list'"

# ---- 8. 第二轮需求断言 ----
check "ssh 要求默认公钥" "grep -q MY_SSH_PUBKEYS modules/ssh.sh"
check "ssh 写 authorized_keys" "grep -q authorized_keys modules/ssh.sh"
check "ssh 首启生成 host key" "grep -q sshdgenkeys modules/ssh.sh"
check "ananicy-cpp 仅 cachyos" "grep -q 'DISTRO == cachyos' modules/gaming.sh"
check "archcn 包接管镜像列表" "grep -q archlinuxcn-mirrorlist-git modules/pacman.sh"
check "original 用 pacman-mirrorlist 包" "grep -q 'pacman_install pacman-mirrorlist' modules/pacman.sh"

# ---- 8b. multilib 由 distro_setup_repos 启用(不依赖 pacman 模块)----
check "arch distro_setup_repos 启用 multilib" "grep -q 'multilib' distro/arch.sh"
check "cachyos distro_setup_repos 启用 multilib" "grep -q 'multilib' distro/cachyos.sh"
check "pacman 模块不再 uncomment multilib 段(已下放 distro)" \
    "! grep -q 's/^#\\[multilib\\]' modules/pacman.sh"

# ---- 9. 内存选项断言 ----
check "mem-zram 与 mem-zswap 互斥" "grep -q 'echo mem-zswap' modules/mem-zram.sh"
check "mem-zswap 与 mem-zram 互斥" "grep -q 'echo mem-zram' modules/mem-zswap.sh"
check "mem-zram 装 zram-generator" "grep -q 'pacman_install zram-generator' modules/mem-zram.sh"
check "mem-zswap 用 tmpfiles 配置" "grep -q 'tmpfiles.d/zswap.conf' modules/mem-zswap.sh"
check "mem-zswap 启用 zstd" "grep -q 'compressor - - - - zstd' modules/mem-zswap.sh"
check "mem-zswap 建 btrfs swapfile" "grep -q 'btrfs filesystem mkswapfile' modules/mem-zswap.sh"
check "mem-zswap 依赖 filesystems" "grep -q 'echo filesystems' modules/mem-zswap.sh"
check "swapfile 大小可配置" "grep -q MY_SWAP_SIZE modules/mem-zswap.sh"
check "MY_SWAP_SIZE=0 退回 zram" "grep -q zram-generator modules/mem-zswap.sh"
check "random-seed 清理" "grep -q 'random-seed' arch-install"
check "pacman.conf UseSyslog" "grep -q 'UseSyslog' modules/pacman.sh"
check "atd 默认启用" "grep -q 'atd.service' modules/cli-tools.sh"
check "镜像稀疏分配" "grep -q 'preallocation=off' lib/disk.sh"
check "镜像清理时 fstrim" "grep -q 'fstrim' lib/disk.sh"
check "config 模板含 MY_SWAP_SIZE" "grep -q MY_SWAP_SIZE config/config.example.sh"
check "boot entry 支持 MY_KERNEL_PARAMS" "grep -q 'MY_KERNEL_PARAMS' lib/disk.sh"
check "config 模板含 MY_KERNEL_PARAMS" "grep -q MY_KERNEL_PARAMS config/config.example.sh"
check "server profile 默认 mem-zswap" "grep -q mem-zswap profiles/server.conf"
check "desktop profile 默认 mem-zswap" "grep -q mem-zswap profiles/desktop.conf"

# ---- 10. GPGPU 模块断言 ----
check "gpgpu 读 MY_GPGPU" "grep -q MY_GPGPU modules/gpgpu.sh"
check "gpgpu 公共包装 ocl-icd+clinfo" "grep -q 'ocl-icd clinfo opencl-headers' modules/gpgpu.sh"
check "gpgpu amd 用 ROCm" "grep -q 'rocm-opencl-runtime rocm-hip-runtime hip-runtime-amd' modules/gpgpu.sh"
check "gpgpu nvidia 用 cuda" "grep -q 'opencl-nvidia cuda' modules/gpgpu.sh"
check "gpgpu intel 用 NEO" "grep -q 'intel-compute-runtime' modules/gpgpu.sh"
check "gpgpu 空值 skip" "grep -q 'return 0' modules/gpgpu.sh"
check "gpgpu 不进 profiles" "! grep -rq gpgpu profiles/"
check "config 模板含 MY_GPGPU" "grep -q MY_GPGPU config/config.example.sh"
check "growfs 补写 fstab x-systemd.growfs" "grep -q 'x-systemd.growfs' modules/growfs.sh"
check "growfs 补丁带行数防护" "grep -q 'fstab.growfs-new' modules/growfs.sh"
check "growfs 不依赖不存在的 GrowFileSystem=" "! grep -q 'GrowFileSystem=' modules/growfs.sh"
check "wait-online 改 --any" "grep -q -- --any modules/network-networkd.sh"
check "ESP 挂载 fmask=0077" "grep -q fmask=0077 lib/disk.sh"

# ---- 11. 设备 profile(--device)----
# 临时设备文件(devices/*.sh 已 gitignore,测试后删除,不污染仓库)
mkdir -p devices
cat >devices/testdev.sh <<'EOF'
DISTRO=cachyos
CPUTYPE=amd
EXTRA_MODULES=gpgpu
MY_HOSTNAME=testdev-host
EOF
device_out=$(./arch-install --target /tmp/x.img --device testdev --dry-run 2>/dev/null)
check "print_plan 显示设备名" "grep -q '设备:      testdev' <<<'$device_out'"
check "--device 固化 distro 生效" "grep -q '发行版:    cachyos' <<<'$device_out'"
check "--device 固化 cputype 生效" "grep -q '微码:      amd' <<<'$device_out'"
check "--device 固化 extra-modules 生效" "grep -qw gpgpu <<<'$device_out'"
cli_over=$(./arch-install --target /tmp/x.img --device testdev --distro arch --dry-run 2>/dev/null)
check "CLI 覆盖设备默认(--distro arch)" "grep -q '发行版:    arch' <<<'$cli_over'"
check "不存在的设备 die" "! ./arch-install --target /tmp/x.img --device nonexist-dev --dry-run >/dev/null 2>&1"
check "非法设备名 die" "! ./arch-install --target /tmp/x.img --device ../etc --dry-run >/dev/null 2>&1"
rm -f devices/testdev.sh
# 叠加顺序断言:main 内 prescan→load_config→load_device→parse_args(函数定义在行首,调用有缩进)
call_order=$(grep -nE '^    (prescan_args|load_config|load_device|parse_args)\b' arch-install | sed 's/^[0-9]*: *//' | cut -d' ' -f1 | paste -sd,)
check "叠加顺序 prescan→config→device→parse" "grep -q 'prescan_args,load_config,load_device,parse_args' <<<'$call_order'"
check "--modules 提前 exit 保留在 prescan" "grep -A5 '^prescan_args()' arch-install | grep -q -- '--modules'"
check "模板 devices/example.sh tracked 例外" "[[ -f devices/example.sh ]] && grep -q '!devices/example.sh' .gitignore"
check "gitignore 忽略 devices/*.sh" "grep -q 'devices/\*.sh' .gitignore"
check "usage 含 --device" "./arch-install --help 2>/dev/null | grep -q -- '--device'"

# ---- 12. 新增安装包断言 ----
check "gui-apps cachyos 装 cachyos-firefox-settings" "grep -q cachyos-firefox-settings modules/gui-apps.sh"
check "gui-apps cachyos-firefox-settings 受 DISTRO 守卫" "grep -q 'DISTRO.*cachyos' modules/gui-apps.sh"
check "dev-tools 含 opencode" "grep -q '\\<opencode\\>' modules/dev-tools.sh"
check "dev-tools 含 shellcheck" "grep -q '\\<shellcheck\\>' modules/dev-tools.sh"
check "desktop-kde cachyos 装 cachyos-themes-sddm" "grep -q cachyos-themes-sddm modules/desktop-kde.sh"
check "cachyos distro_post_install 不装 systemd-boot-manager(/efi+/boot 双区不兼容)" "! grep -qE '^[^#]*systemd-boot-manager' distro/cachyos.sh"

# ---- 13. zfs 模块断言 ----
check "zfs 不进 profiles(--extra-modules 显式启用)" "! grep -rqw zfs profiles/"
check "zfs cachyos 用内核匹配模块包" "grep -q '\\\${KERNEL_PKG}-zfs' modules/zfs.sh"
check "zfs arch 走 archzfs 仓库" "grep -q 'archzfs/zfs-linux' modules/zfs.sh"
check "zfs 用户态工具钉同源仓库(cachyos)" "grep -q 'cachyos/zfs-utils' modules/zfs.sh"
check "zfs 用户态工具钉同源仓库(arch)" "grep -q 'archzfs/zfs-utils' modules/zfs.sh"
check "zfs 启用导入/挂载服务" "grep -q 'zfs-import-cache.service zfs-mount.service' modules/zfs.sh"
check "archzfs 段指向 GitHub Releases 分发" "grep -q 'releases/download/experimental' modules/zfs.sh"
check "--modules 输出含 zfs" "grep -q '^zfs ' <<<'$modules_list'"
check "dry-run 接受 --extra-modules zfs" "./arch-install --target /tmp/x.img --profile server --extra-modules zfs --distro cachyos --cachyos-kernel server --dry-run >/dev/null 2>&1"

# ---- 14. cachyos 仓库等级检测回归(v3-only 宿主误判 v4 → SIGILL) ----
# ld.so 对不支持的级别也输出裸级别名,判定必须带 "(supported" 标记
check "等级检测要求 ld.so supported 标记" "grep -q \"x86-64-v4 (supported'\" distro/cachyos.sh"
check "等级检测不再裸匹配级别字符串" "! grep -q 'grep -q x86-64-v4 <' distro/cachyos.sh"

# ---- 15. 跨等级构建(qemu-user 模拟)----
check "宿主能力与目标等级分离检测" "grep -q '_cachyos_host_level' distro/cachyos.sh"
check "等级序比较函数存在" "grep -q '_cachyos_level_rank' distro/cachyos.sh"
check "动磁盘前预检模拟依赖" "grep -q '_cachyos_preflight_emulation' arch-install"
check "缺 qemu-user-static 时提示安装" "grep -q 'qemu-user-static' lib/chroot.sh"
check "模拟走显式 qemu 前缀执行" "grep -qF 'exec chroot \"\$mnt\" \"\$emu\"' lib/chroot.sh"
check "静态解释器复制进目标系统" "grep -q '_chroot_stage_emulator' lib/chroot.sh"
check "模拟模式设 QEMU_CPU=max" "grep -q 'QEMU_CPU=max' lib/chroot.sh"
check "模拟用静态解释器(chroot 内可用)" "grep -qF 'qemu-x86_64-static' lib/chroot.sh"

# ---- 16. v4 不可模拟硬限制(回归防护)----
# qemu TCG 无 AVX-512(qemu#2878),v4 高于宿主必须拒绝而非尝试模拟
check "预检对超宿主等级直接拒绝" "grep -q '高于宿主执行能力' distro/cachyos.sh"
check "拒绝消息说明 AVX-512 原因" "grep -q 'AVX-512' distro/cachyos.sh"

# ---- 17. ARP 行为修正(多接口机器)----
check "sysctl 设 all.arp_ignore=1" "grep -q 'net.ipv4.conf.all.arp_ignore = 1' modules/sysctl.sh"
check "sysctl 设 default.arp_ignore=1" "grep -q 'net.ipv4.conf.default.arp_ignore = 1' modules/sysctl.sh"
check "sysctl 设 all.arp_announce=2" "grep -q 'net.ipv4.conf.all.arp_announce = 2' modules/sysctl.sh"
check "sysctl 设 default.arp_announce=2" "grep -q 'net.ipv4.conf.default.arp_announce = 2' modules/sysctl.sh"
check "sysctl 不设 lo.arp_*(LVS-DR/VRRP 场景才需要)" "! grep -q 'conf.lo.arp_' modules/sysctl.sh"

# ---- 18. sysctl 审查修正(2026-08-23)----
# mmap_rnd_bits 顶格 32 破坏 LLVM sanitizers(TSan 仅 ≤30 bits),Arch 出厂 28
check "sysctl 不设 mmap_rnd_bits(sanitizer 兼容)" "! grep -qE '^vm\.mmap_rnd' modules/sysctl.sh"
# socket 初始缓冲回落,default 抬高会放大 UDP 内存计账;max 保持供 autotuning
check "sysctl rmem_default 回落 262144" "grep -q 'net.core.rmem_default = 262144' modules/sysctl.sh"
check "sysctl wmem_default 回落 262144" "grep -q 'net.core.wmem_default = 262144' modules/sysctl.sh"
check "sysctl 保持 rmem_max 512MiB" "grep -q 'net.core.rmem_max = 536870912' modules/sysctl.sh"
check "sysctl 保持 wmem_max 512MiB" "grep -q 'net.core.wmem_max = 536870912' modules/sysctl.sh"
# zswap 开启时关闭 swap 预读,仅写在 mem-zswap 的 zswap 路径(非 sysctl 模块)
check "mem-zswap 写 page-cluster=0(sysctl)" "grep -q 'vm.page-cluster = 0' modules/mem-zswap.sh"
check "mem-zswap sysctl 落点 70-zswap.conf" "grep -q '70-zswap.conf' modules/mem-zswap.sh"

# ---- 19. zram 路径补全(2026-08-23)----
# Arch 出厂 CONFIG_ZSWAP_DEFAULT_ON=y,纯 zram 必须关 zswap(双重压缩链)
check "mem-zram 关 zswap(tmpfiles)" "grep -q 'zswap/parameters/enabled - - - - 0' modules/mem-zram.sh"
# Arch Wiki "Optimizing swap on zram"(Pop!_OS/r/Fedora 基准同值)+ 用户指定 vfs_cache_pressure
check "mem-zram sysctl swappiness=180" "grep -q 'vm.swappiness = 180' modules/mem-zram.sh"
check "mem-zram sysctl 关 watermark boost" "grep -q 'vm.watermark_boost_factor = 0' modules/mem-zram.sh"
check "mem-zram sysctl watermark_scale=125" "grep -q 'vm.watermark_scale_factor = 125' modules/mem-zram.sh"
check "mem-zram sysctl page-cluster=0" "grep -q 'vm.page-cluster = 0' modules/mem-zram.sh"
check "mem-zram sysctl vfs_cache_pressure=50" "grep -q 'vm.vfs_cache_pressure = 50' modules/mem-zram.sh"
check "mem-zswap zram 回退分支同款配套" "grep -q '70-zram.conf' modules/mem-zswap.sh && grep -q 'zswap-off.conf' modules/mem-zswap.sh"

[[ ${CLEANUP_CONFIG:-0} == 1 ]] && rm -f config/config.sh

echo
echo "通过 $PASS,失败 $FAIL"
((FAIL == 0))
