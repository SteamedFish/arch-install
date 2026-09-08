#!/usr/bin/env bats
# tests/feature_specifics.bats — sections 7/8/8b/9/10/12-19: 跨模块专项断言
# 把大量 check 转 @test,保证失败定位精确
# shellcheck disable=SC2314  # bats 中 `! assert_*` 是合法且唯一的最后命令,SC2314 误报
load test_helper
setup() {
    setup_repo_root
    ensure_dryrun_config
}
teardown() {
    if [[ ${DRYRUN_CLEANUP_CONFIG:-0} == 1 ]]; then
        rm -f config/config.sh
    fi
}

# ============================================================
# section 7: 专项断言
# ============================================================

@test "section 7: debug 模块存在" {                   [[ -f modules/debug.sh ]]; }
@test "section 7: gaming 含 archlinuxcn 包(an-anime-game-launcher-bwrap)" {
    assert_file_contains modules/gaming.sh 'an-anime-game-launcher-bwrap'
}
@test "section 7: cachyos 查询最新版(_cachyos_latest_pkg_url)" {
    assert_file_contains distro/cachyos.sh '_cachyos_latest_pkg_url'
}
@test "section 7: cachyos 支持自有 mirrorlist(MY_CACHYOS_MIRRORLIST)" {
    assert_file_contains distro/cachyos.sh 'MY_CACHYOS_MIRRORLIST'
}
@test "section 7: arch-install 支持 --cputype" {
    assert_file_contains arch-install -- '--cputype'
}
@test "section 7: KDE 专属应用在 desktop-kde(dolphin)" {
    assert_word_in_file modules/desktop-kde.sh 'dolphin'
}
@test "section 7: gui-apps 不含 KDE 系统应用(dolphin/kate)" {
    ! grep -qwE 'dolphin|kate' modules/gui-apps.sh
}
@test "section 7: gui-apps 含 neochat(社交客户端)" {
    assert_word_in_file modules/gui-apps.sh 'neochat'
}
@test "section 7: gui-apps 含 tokodon(社交客户端)" {
    assert_word_in_file modules/gui-apps.sh 'tokodon'
}
@test "section 7: desktop-kde 不再含 neochat" {
    ! grep -qw 'neochat' modules/desktop-kde.sh
}
@test "section 7: desktop-kde 不再含 tokodon" {
    ! grep -qw 'tokodon' modules/desktop-kde.sh
}
@test "section 7: --modules 输出含 desktop-niri" {
    modules_list=$(./arch-install --modules 2>/dev/null)
    assert_str_contains "$modules_list" "desktop-niri"
}
@test "section 7: desktop-niri 原生 swaylock 仅非 cachyos 分支" {
    assert_file_contains_literal modules/desktop-niri.sh 'pkgs+=(swaylock)'
}
@test "section 7: desktop-niri 不再无条件装原生 swaylock(swaybg swaylock 一行)" {
    ! assert_file_contains modules/desktop-niri.sh 'swaybg swaylock'
}
@test "section 7: desktop-niri 装 cachyos-niri-settings(含 swaylock-effects-git)" {
    assert_file_contains modules/desktop-niri.sh 'pacman_install cachyos-niri-settings'
}

# ============================================================
# section 8: 第二轮需求断言
# ============================================================

@test "section 8: ssh 要求默认公钥(MY_SSH_PUBKEYS)" {
    assert_file_contains modules/ssh.sh 'MY_SSH_PUBKEYS'
}
@test "section 8: ssh 写 authorized_keys" {
    assert_file_contains modules/ssh.sh 'authorized_keys'
}
@test "section 8: ssh 首启生成 host key(sshdgenkeys)" {
    assert_file_contains modules/ssh.sh 'sshdgenkeys'
}
@test "section 8: ananicy-cpp 仅 cachyos" {
    assert_file_contains modules/gaming.sh 'DISTRO == cachyos'
}
@test "section 8: archcn 包接管镜像列表(archlinuxcn-mirrorlist-git)" {
    assert_file_contains modules/pacman.sh 'archlinuxcn-mirrorlist-git'
}
@test "section 8: original 用 pacman-mirrorlist 包" {
    assert_file_contains modules/pacman.sh 'pacman_install pacman-mirrorlist'
}

# ============================================================
# section 8b: multilib 由 distro_setup_repos 启用
# ============================================================

@test "section 8b: arch distro_setup_repos 启用 multilib" {
    assert_file_contains distro/arch.sh 'multilib'
}
@test "section 8b: cachyos distro_setup_repos 启用 multilib" {
    assert_file_contains distro/cachyos.sh 'multilib'
}
@test "section 8b: pacman 模块不再 uncomment multilib 段(已下放 distro)" {
    ! assert_file_contains modules/pacman.sh 's/^#\[multilib\]'
}

# ============================================================
# section 9: 内存选项断言
# ============================================================

@test "section 9: mem-zram 与 mem-zswap 互斥" {
    assert_file_contains modules/mem-zram.sh 'echo mem-zswap'
}
@test "section 9: mem-zswap 与 mem-zram 互斥" {
    assert_file_contains modules/mem-zswap.sh 'echo mem-zram'
}
@test "section 9: mem-zram 装 zram-generator" {
    assert_file_contains modules/mem-zram.sh 'pacman_install zram-generator'
}
@test "section 9: mem-zswap 用 tmpfiles 配置" {
    assert_file_contains modules/mem-zswap.sh 'tmpfiles.d/zswap.conf'
}
@test "section 9: mem-zswap 启用 zstd(compressor)" {
    assert_file_contains modules/mem-zswap.sh 'compressor - - - - zstd'
}
@test "section 9: mem-zswap 建 btrfs swapfile" {
    assert_file_contains modules/mem-zswap.sh 'btrfs filesystem mkswapfile'
}
@test "section 9: mem-zswap 依赖 filesystems" {
    assert_file_contains modules/mem-zswap.sh 'echo filesystems'
}
@test "section 9: swapfile 大小可配置(MY_SWAP_SIZE)" {
    assert_file_contains modules/mem-zswap.sh 'MY_SWAP_SIZE'
}
@test "section 9: MY_SWAP_SIZE=0 退回 zram" {
    assert_file_contains modules/mem-zswap.sh 'zram-generator'
}
@test "section 9: random-seed 清理" {
    assert_file_contains arch-install 'random-seed'
}
@test "section 9: pacman.conf UseSyslog" {
    assert_file_contains modules/pacman.sh 'UseSyslog'
}
@test "section 9: atd 默认启用" {
    assert_file_contains modules/cli-tools.sh 'atd.service'
}
@test "section 9: 镜像稀疏分配(preallocation=off)" {
    assert_file_contains lib/disk.sh 'preallocation=off'
}
@test "section 9: 镜像清理时 fstrim" {
    assert_file_contains lib/disk.sh 'fstrim'
}
@test "section 9: config 模板含 MY_SWAP_SIZE" {
    assert_file_contains config/config.example.sh 'MY_SWAP_SIZE'
}
@test "section 9: boot entry 支持 MY_KERNEL_PARAMS" {
    assert_file_contains lib/disk.sh 'MY_KERNEL_PARAMS'
}
@test "section 9: config 模板含 MY_KERNEL_PARAMS" {
    assert_file_contains config/config.example.sh 'MY_KERNEL_PARAMS'
}
@test "section 9: server profile 默认 mem-zswap" {
    assert_file_contains profiles/server.conf 'mem-zswap'
}
@test "section 9: desktop profile 默认 mem-zswap" {
    assert_file_contains profiles/desktop.conf 'mem-zswap'
}

# ============================================================
# section 10: GPGPU 模块断言
# ============================================================

@test "section 10: gpgpu 读 MY_GPGPU" {
    assert_file_contains modules/gpgpu.sh 'MY_GPGPU'
}
@test "section 10: gpgpu 公共包装 ocl-icd+clinfo" {
    assert_file_contains modules/gpgpu.sh 'ocl-icd clinfo opencl-headers'
}
@test "section 10: gpgpu amd 用 ROCm" {
    assert_file_contains modules/gpgpu.sh 'rocm-opencl-runtime rocm-hip-runtime hip-runtime-amd'
}
@test "section 10: gpgpu nvidia 用 cuda" {
    assert_file_contains modules/gpgpu.sh 'opencl-nvidia cuda'
}
@test "section 10: gpgpu intel 用 NEO" {
    assert_file_contains modules/gpgpu.sh 'intel-compute-runtime'
}
@test "section 10: gpgpu 空值 skip" {
    assert_file_contains modules/gpgpu.sh 'return 0'
}
@test "section 10: gpgpu 不进 profiles" {
    assert_dirs_no_match profiles -- 'gpgpu'
}
@test "section 10: config 模板含 MY_GPGPU" {
    assert_file_contains config/config.example.sh 'MY_GPGPU'
}
@test "section 10: growfs 补写 fstab x-systemd.growfs" {
    assert_file_contains modules/growfs.sh 'x-systemd.growfs'
}
@test "section 10: growfs 补丁带行数防护(fstab.growfs-new)" {
    assert_file_contains modules/growfs.sh 'fstab.growfs-new'
}
@test "section 10: growfs 不依赖不存在的 GrowFileSystem=" {
    ! assert_file_contains modules/growfs.sh 'GrowFileSystem='
}
@test "section 10: wait-online 改 --any" {
    assert_file_contains modules/network-networkd.sh -- --any
}
@test "section 10: ESP 挂载 fmask=0077" {
    assert_file_contains lib/disk.sh 'fmask=0077'
}
@test "section 10: btrfs journal NOCOW(chattr +C)" {
    assert_file_contains_literal lib/disk.sh 'chattr +C'
}
@test "section 10: NOCOW 仅 btrfs 根(fstype 守卫)" {
    assert_file_contains lib/disk.sh 'output FSTYPE'
    assert_file_contains lib/disk.sh 'fstype != btrfs'
}
@test "section 10: 主入口给 /var/log/journal 设 NOCOW" {
    assert_file_contains arch-install 'btrfs_nocow_dir /var/log/journal'
}
@test "section 10: auditd 给 /var/log/audit 设 NOCOW" {
    assert_file_contains modules/auditd.sh 'btrfs_nocow_dir /var/log/audit'
}
@test "section 10: virt 给 /var/lib/libvirt/images 设 NOCOW" {
    assert_file_contains modules/virt.sh 'btrfs_nocow_dir /var/lib/libvirt/images'
}

# ============================================================
# section 12: 新增安装包断言
# ============================================================

@test "section 12: gui-apps cachyos 装 cachyos-firefox-settings" {
    assert_file_contains modules/gui-apps.sh 'cachyos-firefox-settings'
}
@test "section 12: gui-apps cachyos-firefox-settings 受 DISTRO 守卫" {
    assert_file_contains modules/gui-apps.sh 'DISTRO.*cachyos'
}
@test "section 12: dev-tools 含 opencode" {
    assert_word_in_file modules/dev-tools.sh 'opencode'
}
@test "section 12: dev-tools 含 shellcheck" {
    assert_word_in_file modules/dev-tools.sh 'shellcheck'
}
@test "section 12: dev-tools 含 bash-language-server" {
    assert_word_in_file modules/dev-tools.sh 'bash-language-server'
}
@test "section 12: dev-tools 含 bats" {
    assert_word_in_file modules/dev-tools.sh 'bats'
}
@test "section 12: dev-tools 含 lua-language-server" {
    assert_word_in_file modules/dev-tools.sh 'lua-language-server'
}
@test "section 12: dev-tools 含 ruff" {
    assert_word_in_file modules/dev-tools.sh 'ruff'
}
@test "section 12: dev-tools 含 uv" {
    assert_word_in_file modules/dev-tools.sh 'uv'
}
@test "section 12: dev-tools 含 biome" {
    assert_word_in_file modules/dev-tools.sh 'biome'
}
@test "section 12: dev-tools 含 yaml-language-server" {
    assert_word_in_file modules/dev-tools.sh 'yaml-language-server'
}
@test "section 12: dev-tools 含 pyright" {
    assert_word_in_file modules/dev-tools.sh 'pyright'
}
@test "section 12: dev-tools 含 gopls" {
    assert_word_in_file modules/dev-tools.sh 'gopls'
}
@test "section 12: dev-tools 含 rust-analyzer" {
    assert_word_in_file modules/dev-tools.sh 'rust-analyzer'
}
@test "section 12: dev-tools 不含 wakatime(AUR-only)" {
    ! assert_line_match modules/dev-tools.sh '^\s+pacman_install.*wakatime'
}
@test "section 12: dev-tools 不含 yadm(归 base)" {
    ! assert_line_match modules/dev-tools.sh '^\s+pacman_install.*yadm'
}
@test "section 12: dev-tools 不含 git-crypt(归 security)" {
    ! assert_line_match modules/dev-tools.sh '^\s+pacman_install.*git-crypt'
}
@test "section 12: dev-tools 不含 pass/passff-host(归 security)" {
    ! assert_line_match modules/dev-tools.sh '^\s+pacman_install.*(pass|passff-host)'
}
@test "section 12: dev-tools 不含 shfmt(cli-tools 已含)" {
    ! assert_line_match modules/dev-tools.sh '^\s+pacman_install.*shfmt'
}
@test "section 12: security 含 pass" {
    assert_word_in_file modules/security.sh 'pass'
}
@test "section 12: security 含 passff-host" {
    assert_word_in_file modules/security.sh 'passff-host'
}
@test "section 12: security 含 git-crypt" {
    assert_word_in_file modules/security.sh 'git-crypt'
}
@test "section 12: base 无条件装 yadm(zsh yadm 一行)" {
    assert_file_contains modules/base.sh 'pacman_install zsh yadm'
}
@test "section 12: keyfile 分支不重复装 yadm(git git-crypt yadm)" {
    ! assert_file_contains modules/base.sh 'pacman_install git git-crypt yadm'
}
@test "section 12: cli-tools 含 shfmt(历史归属)" {
    assert_word_in_file modules/cli-tools.sh 'shfmt'
}
@test "section 12: desktop-kde cachyos 装 cachyos-themes-sddm" {
    assert_file_contains modules/desktop-kde.sh 'cachyos-themes-sddm'
}
@test "section 12: cachyos distro_post_install 不装 systemd-boot-manager(/efi+/boot 双区不兼容)" {
    ! assert_line_match distro/cachyos.sh '^[^#]*systemd-boot-manager'
}

# ============================================================
# section 13: zfs 模块断言
# ============================================================

@test "section 13: zfs 不进 profiles(--extra-modules 显式启用)" {
    ! grep -rqw zfs profiles/
}
@test "section 13: zfs cachyos 用内核匹配模块包(\${KERNEL_PKG}-zfs)" {
    assert_file_contains modules/zfs.sh '\$\{KERNEL_PKG\}-zfs'
}
@test "section 13: zfs arch 走 archzfs 仓库(zfs-linux)" {
    assert_file_contains modules/zfs.sh 'archzfs/zfs-linux'
}
@test "section 13: zfs 用户态工具钉同源仓库(cachyos)" {
    assert_file_contains modules/zfs.sh 'cachyos/zfs-utils'
}
@test "section 13: zfs 用户态工具钉同源仓库(arch)" {
    assert_file_contains modules/zfs.sh 'archzfs/zfs-utils'
}
@test "section 13: zfs 启用导入/挂载服务" {
    assert_file_contains modules/zfs.sh 'zfs-import-cache.service zfs-mount.service'
}
@test "section 13: archzfs 段指向 GitHub Releases 分发" {
    assert_file_contains modules/zfs.sh 'releases/download/experimental'
}
@test "section 13: --modules 输出含 zfs" {
    modules_list=$(./arch-install --modules 2>/dev/null)
    assert_str_contains "$modules_list" "zfs"
}
@test "section 13: dry-run 接受 --extra-modules zfs" {
    ./arch-install --target /tmp/x.img --profile server --extra-modules zfs \
        --distro cachyos --cachyos-kernel server --dry-run >/dev/null 2>&1
}

# ============================================================
# section 14: cachyos 仓库等级检测回归
# ============================================================

@test "section 14: 等级检测要求 ld.so supported 标记" {
    assert_file_contains_literal distro/cachyos.sh "x86-64-v4 (supported'"
}
@test "section 14: 等级检测不再裸匹配级别字符串" {
    ! assert_file_contains distro/cachyos.sh 'grep -q x86-64-v4 <'
}

# ============================================================
# section 15: 跨等级构建(qemu-user 模拟)
# ============================================================

@test "section 15: 宿主能力与目标等级分离检测(_cachyos_host_level)" {
    assert_file_contains distro/cachyos.sh '_cachyos_host_level'
}
@test "section 15: 等级序比较函数存在(_cachyos_level_rank)" {
    assert_file_contains distro/cachyos.sh '_cachyos_level_rank'
}
@test "section 15: 动磁盘前预检模拟依赖(_cachyos_preflight_emulation)" {
    assert_file_contains arch-install '_cachyos_preflight_emulation'
}
@test "section 15: 缺 qemu-user-static 时提示安装" {
    assert_file_contains lib/chroot.sh 'qemu-user-static'
}
@test "section 15: 模拟走显式 qemu 前缀执行" {
    # shellcheck disable=SC2016  # 字面匹配(grep -F),$ 是源码字符不是变量
    grep -qF 'exec chroot "$mnt" "$emu"' lib/chroot.sh
}
@test "section 15: 静态解释器复制进目标系统(_chroot_stage_emulator)" {
    assert_file_contains lib/chroot.sh '_chroot_stage_emulator'
}
@test "section 15: 模拟模式设 QEMU_CPU=max" {
    assert_file_contains lib/chroot.sh 'QEMU_CPU=max'
}
@test "section 15: 模拟用静态解释器(qemu-x86_64-static)" {
    grep -qF 'qemu-x86_64-static' lib/chroot.sh
}

# ============================================================
# section 16: v4 不可模拟硬限制(回归防护)
# ============================================================

@test "section 16: 预检对超宿主等级直接拒绝" {
    assert_file_contains distro/cachyos.sh '高于宿主执行能力'
}
@test "section 16: 拒绝消息说明 AVX-512 原因" {
    assert_file_contains distro/cachyos.sh 'AVX-512'
}

# ============================================================
# section 17: ARP 行为修正(多接口机器)
# ============================================================

@test "section 17: sysctl 设 all.arp_ignore=1" {
    assert_file_contains modules/sysctl.sh 'net.ipv4.conf.all.arp_ignore = 1'
}
@test "section 17: sysctl 设 default.arp_ignore=1" {
    assert_file_contains modules/sysctl.sh 'net.ipv4.conf.default.arp_ignore = 1'
}
@test "section 17: sysctl 设 all.arp_announce=2" {
    assert_file_contains modules/sysctl.sh 'net.ipv4.conf.all.arp_announce = 2'
}
@test "section 17: sysctl 设 default.arp_announce=2" {
    assert_file_contains modules/sysctl.sh 'net.ipv4.conf.default.arp_announce = 2'
}
@test "section 17: sysctl 不设 lo.arp_*(LVS-DR/VRRP 才需要)" {
    ! assert_file_contains modules/sysctl.sh 'conf.lo.arp_'
}

# ============================================================
# section 18: sysctl 审查修正(2026-08-23)
# ============================================================

@test "section 18: sysctl 不设 mmap_rnd_bits(sanitizer 兼容)" {
    ! assert_file_contains modules/sysctl.sh '^vm\.mmap_rnd'
}
@test "section 18: sysctl rmem_default 回落 262144" {
    assert_file_contains modules/sysctl.sh 'net.core.rmem_default = 262144'
}
@test "section 18: sysctl wmem_default 回落 262144" {
    assert_file_contains modules/sysctl.sh 'net.core.wmem_default = 262144'
}
@test "section 18: sysctl 保持 rmem_max 512MiB" {
    assert_file_contains modules/sysctl.sh 'net.core.rmem_max = 536870912'
}
@test "section 18: sysctl 保持 wmem_max 512MiB" {
    assert_file_contains modules/sysctl.sh 'net.core.wmem_max = 536870912'
}
@test "section 18: mem-zswap 写 page-cluster=0(sysctl)" {
    assert_file_contains modules/mem-zswap.sh 'vm.page-cluster = 0'
}
@test "section 18: mem-zswap sysctl 落点 70-zswap.conf" {
    assert_file_contains modules/mem-zswap.sh '70-zswap.conf'
}

# ============================================================
# section 19: zram 路径补全(2026-08-23)
# ============================================================

@test "section 19: mem-zram 关 zswap(tmpfiles)" {
    assert_file_contains modules/mem-zram.sh 'zswap/parameters/enabled - - - - 0'
}
@test "section 19: mem-zram sysctl swappiness=180" {
    assert_file_contains modules/mem-zram.sh 'vm.swappiness = 180'
}
@test "section 19: mem-zram sysctl 关 watermark boost" {
    assert_file_contains modules/mem-zram.sh 'vm.watermark_boost_factor = 0'
}
@test "section 19: mem-zram sysctl watermark_scale=125" {
    assert_file_contains modules/mem-zram.sh 'vm.watermark_scale_factor = 125'
}
@test "section 19: mem-zram sysctl page-cluster=0" {
    assert_file_contains modules/mem-zram.sh 'vm.page-cluster = 0'
}
@test "section 19: mem-zram sysctl vfs_cache_pressure=50" {
    assert_file_contains modules/mem-zram.sh 'vm.vfs_cache_pressure = 50'
}
@test "section 19: mem-zswap zram 回退分支同款配套" {
    assert_file_contains modules/mem-zswap.sh '70-zram.conf'
    assert_file_contains modules/mem-zswap.sh 'zswap-off.conf'
}
