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
check "desktop-niri 原生 swaylock 仅非 cachyos 分支" "grep -q 'pkgs+=(swaylock)' modules/desktop-niri.sh"
check "desktop-niri 不再无条件装原生 swaylock" "! grep -q 'swaybg swaylock' modules/desktop-niri.sh"
check "desktop-niri 装 cachyos-niri-settings(含 swaylock-effects-git)" "grep -q 'pacman_install cachyos-niri-settings' modules/desktop-niri.sh"

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
check "btrfs journal NOCOW(chattr +C)" "grep -q 'chattr +C' lib/disk.sh"
check "NOCOW 仅 btrfs 根(fstype 守卫)" "grep -q 'output FSTYPE' lib/disk.sh && grep -q 'fstype != btrfs' lib/disk.sh"
check "主入口给 /var/log/journal 设 NOCOW" "grep -q 'btrfs_nocow_dir /var/log/journal' arch-install"
check "auditd 给 /var/log/audit 设 NOCOW" "grep -q 'btrfs_nocow_dir /var/log/audit' modules/auditd.sh"
check "virt 给 /var/lib/libvirt/images 设 NOCOW" "grep -q 'btrfs_nocow_dir /var/lib/libvirt/images' modules/virt.sh"

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
check "dev-tools 含 bash-language-server" "grep -q '\\<bash-language-server\\>' modules/dev-tools.sh"
check "dev-tools 含 lua-language-server" "grep -q '\\<lua-language-server\\>' modules/dev-tools.sh"
check "dev-tools 含 ruff" "grep -q '\\<ruff\\>' modules/dev-tools.sh"
check "dev-tools 含 uv" "grep -q '\\<uv\\>' modules/dev-tools.sh"
check "dev-tools 含 biome" "grep -q '\\<biome\\>' modules/dev-tools.sh"
check "dev-tools 含 yaml-language-server" "grep -q '\\<yaml-language-server\\>' modules/dev-tools.sh"
check "dev-tools 含 pyright" "grep -q '\\<pyright\\>' modules/dev-tools.sh"
check "dev-tools 含 gopls" "grep -q '\\<gopls\\>' modules/dev-tools.sh"
check "dev-tools 含 rust-analyzer" "grep -q '\\<rust-analyzer\\>' modules/dev-tools.sh"
check "dev-tools 不含 wakatime(AUR-only)" "! grep -E '^\s+pacman_install.*wakatime' modules/dev-tools.sh"
check "dev-tools 不含 yadm(dotfiles 归 base)" "! grep -E '^\s+pacman_install.*yadm' modules/dev-tools.sh"
check "dev-tools 不含 git-crypt(归 security)" "! grep -E '^\s+pacman_install.*git-crypt' modules/dev-tools.sh"
check "dev-tools 不含 pass/passff-host(密码管理归 security)" "! grep -E '^\s+pacman_install.*(pass|passff-host)' modules/dev-tools.sh"
check "dev-tools 不含 shfmt(cli-tools 已含)" "! grep -E '^\s+pacman_install.*shfmt' modules/dev-tools.sh"
check "security 含 pass" "grep -q '\\<pass\\>' modules/security.sh"
check "security 含 passff-host" "grep -q '\\<passff-host\\>' modules/security.sh"
check "security 含 git-crypt" "grep -q '\\<git-crypt\\>' modules/security.sh"
check "base 无条件装 yadm" "grep -q 'pacman_install zsh yadm' modules/base.sh"
check "keyfile 分支不重复装 yadm" "! grep -q 'pacman_install git git-crypt yadm' modules/base.sh"
check "cli-tools 含 shfmt(历史归属)" "grep -q '\\<shfmt\\>' modules/cli-tools.sh"
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

# ---- 20. firewall 迁移 nftables(2026-08-23)----
# Arch 原生开机加载:nftables.service(ExecStart=nft -f /etc/nftables.conf)
check "firewall 装 nftables 包" "grep -q 'pacman_install nftables' modules/firewall.sh"
check "firewall 写 /etc/nftables.conf" "grep -q '/etc/nftables.conf' modules/firewall.sh"
check "nftables 用 inet filter 单表统一 v4/v6" "grep -q 'table inet filter' modules/firewall.sh"
check "input 链 policy drop" "grep -q 'policy drop' modules/firewall.sh"
check "放行 established/related" "grep -q 'ct state established,related accept' modules/firewall.sh"
check "放行 ICMPv6(NDP 必需)" "grep -q 'meta l4proto ipv6-icmp' modules/firewall.sh"
check "flush ruleset 保证 service 重启幂等" "grep -q 'flush ruleset' modules/firewall.sh"
check "开机加载走 nftables.service" "grep -q 'chroot_enable nftables.service' modules/firewall.sh"
check "SSH 端口仍读 MY_SSH_PORT(与 ssh 模块一致)" "grep -q MY_SSH_PORT modules/firewall.sh"
check "不再写 /etc/iptables 规则文件" "! grep -q '/etc/iptables/' modules/firewall.sh"
check "不再 enable iptables/ip6tables 服务" "! grep -qE '(iptables|ip6tables)\\.service' modules/firewall.sh"

# ---- 21. alarm(aarch64)支持 ----
check "distro/alarm.sh 存在" "[[ -f distro/alarm.sh ]]"
check "alarm 定义四函数契约" "grep -q '^distro_base_packages()' distro/alarm.sh && grep -q '^distro_setup_repos()' distro/alarm.sh && grep -q '^distro_kernel_packages()' distro/alarm.sh && grep -q '^distro_post_install()' distro/alarm.sh"
check "alarm 定义 distro_host_preflight" "grep -q '^distro_host_preflight()' distro/alarm.sh"
check "alarm preflight 检查 binfmt qemu-aarch64" "grep -q 'binfmt_misc/qemu-aarch64' distro/alarm.sh"
check "alarm preflight 检查 F flag" "grep -q 'flags:.*F' distro/alarm.sh"
check "alarm 构建密钥指纹" "grep -q '68B3537F39A313B3E574D06777193F152BDBE6A6' distro/alarm.sh"
check "alarm base_packages 显式含 archlinuxarm-keyring" "grep -q 'archlinuxarm-keyring' distro/alarm.sh"
check "alarm base_packages 无 efifs(alarm 无此包)" "! grep -qE 'echo .*efifs' distro/alarm.sh"
check "alarm 数据库不签名 DatabaseOptional" "grep -q 'Required DatabaseOptional' distro/alarm.sh"
check "alarm 四仓库段 core/extra/alarm/aur" "grep -q '^\[alarm\]' distro/alarm.sh && grep -q '^\[aur\]' distro/alarm.sh"
check "alarm 内核包 linux-aarch64" "grep -q 'KERNEL_PKG=linux-aarch64' distro/alarm.sh"
check "alarm autodetect 备份恢复法" "grep -q 'mkinitcpio.conf.alarm-orig' distro/alarm.sh"
check "alarm 不做 pacman-key --init(pacstrap -K 已做)" "! grep -q 'pacman-key --init' distro/alarm.sh"
check "alarm 做 pacman-key --populate" "grep -q 'pacman-key --populate archlinuxarm' distro/alarm.sh"
check "alarm dtb override 到 /efi/dtb/base" "grep -q '/efi/dtb/base' distro/alarm.sh"
check "alarm 读 MY_ALARM_MIRROR" "grep -q 'MY_ALARM_MIRROR' distro/alarm.sh"
check "alarm 无 multilib(aarch64 无此概念)" "! grep -qi multilib distro/alarm.sh"
check "--distro 白名单含 alarm" "grep -q 'DISTRO == alarm' arch-install"
check "alarm 强制 CPUTYPE=generic" "grep -q 'CPUTYPE=generic' arch-install"
check "主入口守卫调用 distro_host_preflight" "grep -q 'declare -F distro_host_preflight' arch-install"
check "alarm 镜像末尾提示 dd 而非 qemu-x86" "grep -q 'alarm(aarch64)镜像' arch-install"
check "dry-run alarm" "./arch-install --target /tmp/x.img --profile server --distro alarm --dry-run >/dev/null 2>&1"
check "base.sh 支持 PACSTRAP_CONF(-C/-M)" "grep -q 'PACSTRAP_CONF' modules/base.sh"
check "pacstrap -K 保留不变" "grep -q 'pacstrap_args=(-K)' modules/base.sh"
check "根分区 GUID 按架构(ARM-64 DPS)" "grep -q 'B921B045-1DF0-41C3-AF44-4C6F280D3FAE' lib/disk.sh"
check "alarm XBOOTLDR 用 FAT32(无 efifs)" "grep -q 'mkfs.fat -n \"Linux Boot\"' lib/disk.sh"
check "x86 XBOOTLDR 仍是 ext4" "grep -q 'mkfs.ext4 -F -L \"Linux Boot\"' lib/disk.sh"
check "alarm 引导项用 /Image(PE-stub;Image.gz 不可加载)" "grep -q 'linux   /Image' lib/disk.sh"
check "alarm 引导项 initramfs-linux.img" "grep -q 'initrd  /initramfs-linux.img' lib/disk.sh"
check "alarm 引导项标题 Arch Linux ARM" "grep -q 'Arch Linux ARM' lib/disk.sh"
check "alarm 引导项无 add_efi_memmap(x86-only)" "! awk '/linux   \/Image/,/^    else/' lib/disk.sh | grep -qE 'options.*add_efi_memmap'"
check "alarm 分支不写 fallback 条目(内核包名≠preset 名)" "! awk '/linux   \/Image/,/^    else/' lib/disk.sh | grep -qE 'fallback[.]conf|initramfs-.*-fallback'"
check "hardware turbostat 有 alarm 门禁(x86-only)" "grep -q 'pkgs+=(turbostat)' modules/hardware.sh"
check "hardware linux-tools-meta 保留(alarm 存在)" "grep -q 'linux-tools-meta' modules/hardware.sh"
check "dev-tools opencode 有 alarm 门禁(alarm 404)" "grep -q 'pkgs+=(opencode)' modules/dev-tools.sh"
check "dev-tools LSP/formatter 保留(alarm 存在)" "grep -q 'bash-language-server' modules/dev-tools.sh && grep -q 'biome' modules/dev-tools.sh && grep -q 'rust-analyzer' modules/dev-tools.sh"
check "pacman mirrorlist 四模式跳过 alarm" "grep -q 'DISTRO:-arch} != alarm' modules/pacman.sh"
check "pacman archlinuxcn 段保留(cn 有 aarch64 仓)" "grep -q 'archlinuxcn-keyring' modules/pacman.sh"

# qemu-user 模拟下 pacman 7.1 下载沙箱必死(Landlock/seccomp syscall 不被
# qemu-user 翻译;触发项是出厂 pacman.conf 的 DownloadUser=alpm)→ alarm 的
# chroot pacman 一律带 --disable-sandbox;镜像内恢复出厂等价配置
# (repro: loop+btrfs chroot 内出厂 conf 下载必现,--disable-sandbox 或
# 注释 DownloadUser 即恢复;x86 原生 chroot 不受影响)
check "pacman_install 在 alarm 下传 --disable-sandbox(qemu-user 无 Landlock)" "grep -q 'DISTRO:-arch} == alarm.*&& sandbox' lib/chroot.sh"
check "pacman_install 的 --disable-sandbox 有 DISTRO 守卫(x86 不受影响)" "! grep -q 'pacman -S --needed --noconfirm --disable-sandbox' lib/chroot.sh"
check "alarm 的 pacman -Syu 带 --disable-sandbox(同上)" "grep -q 'pacman -Syu --noconfirm --disable-sandbox' distro/alarm.sh"
check "alarm 目标 pacman.conf 含 DownloadUser=alpm(出厂对齐;CLI flag 不污染镜像)" "grep -q '^DownloadUser = alpm' distro/alarm.sh"

# mkinitcpio 是内核包的依赖,distro_kernel_packages 被主入口调用时内核还没装
# (实测:cp /mnt/etc/mkinitcpio.conf 报 No such file or directory);且内核安装
# 的 90-mkinitcpio-install hook 在同事务内就会用该 conf 建 initramfs,所以
# 必须先显式装 mkinitcpio 再 sed 它的 conf
check "alarm 先装 mkinitcpio 再改 conf(内核依赖时序)" "grep -q 'pacman_install mkinitcpio' distro/alarm.sh"
check "cli-tools yay 保留(cn aarch64 提供)" "grep -qw yay modules/cli-tools.sh"
check "config 模板含 MY_ALARM_MIRROR" "grep -q MY_ALARM_MIRROR config/config.example.sh"
check "devices 模板含 alarm 示例" "grep -q 'DISTRO=alarm' devices/example.sh"
check ".gitignore 含 .tmp(bootstrap conf 临时目录)" "grep -q '^\.tmp' .gitignore"
check "README 双语文档提及 Arch Linux ARM" "grep -q 'Arch Linux ARM' README.md && grep -q 'Arch Linux ARM' README.zh-CN.md"
check "AGENTS 目录结构含 distro/alarm.sh" "grep -q 'distro/alarm\.sh' AGENTS.md"

[[ ${CLEANUP_CONFIG:-0} == 1 ]] && rm -f config/config.sh

echo
echo "通过 $PASS,失败 $FAIL"
((FAIL == 0))
