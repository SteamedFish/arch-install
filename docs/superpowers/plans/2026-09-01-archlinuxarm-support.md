# Arch Linux ARM (aarch64) 支持实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 arch-install 增加 `alarm`(Arch Linux ARM aarch64)distro 后端,在 x86_64 宿主上构建 Orange Pi 5 Plus(RK3588,edk2-rk3588 UEFI)可 dd 的 server 镜像(mainline 内核 linux-aarch64)。

**Architecture:** 新增 `distro/alarm.sh` 实现既有四函数 distro 契约 + 可选 `distro_host_preflight`(binfmt 检查/宿主 keyring 导入/bootstrap pacman.conf);主入口与 lib/disk.sh 做架构泛化(GUID、XBOOTLDR FAT32、引导项 Image 命名);跨架构执行依赖宿主 binfmt_misc(F flag)+ qemu-aarch64-static。分区/引导布局不变(ESP /efi + XBOOTLDR /boot + btrfs 根)。

**Tech Stack:** 纯 bash;pacstrap -C/-M;pacman-key;systemd-boot(bootctl);qemu-user-static binfmt。

**Spec:** `docs/superpowers/specs/2026-09-01-archlinuxarm-support-design.md`(执行者必读,计划中的每条理由都在 spec 里有出处)

**工作目录:** `.worktrees/alarm-aarch64`(分支 `feat/alarm-aarch64`)。所有路径相对于该 worktree 根。

## Global Constraints

- 模块内禁止硬编码个人信息;只读 `MY_*` 变量,为空则 skip(AGENTS.md 硬约定)
- 同一功能的装包/配置/enable 必须在同一模块文件内
- 安装顺序敏感处必须注释原因(pacman 字母序坑)
- `pacman_install` 后自动 `pacman -Sc`(既有 lib/chroot.sh 行为,不用管)
- 每个 commit 必须 GPG 签名(repo 已配 commit.gpgsign=true,直接 git commit 即可;gpg-agent 锁定时让用户解锁)
- 模块里的 distro 判断一律用 `${DISTRO:-arch}` 防御性写法(模块可能被单测 source)
- **不得破坏 x86 路径**:tests/run.sh 现有断言(303 项)必须全部保持通过
- 新测试统一加在 tests/run.sh 末尾新小节 `# ---- 21. alarm(aarch64)----`,插在第 309 行 `[[ ${CLEANUP_CONFIG:-0} == 1 ]] ...` 之前
- 注释用中文,与现有文件风格一致;commit message 沿用仓库风格(如 `feat(distro): ...`)
- alarm 关键事实(spec §3,写代码时当注释依据):
  - alarm 仓库数据库不签名(上游设计)→ `SigLevel = Required DatabaseOptional`
  - alarm 构建密钥:`68B3537F39A313B3E574D06777193F152BDBE6A6`
  - pacstrap 验签走**宿主** keyring;-K 只对目标 keyring 做 --init(/usr/bin/pacstrap:208-218 实测)
  - alarm 内核包 `linux-aarch64` → `/boot/Image`(PE-stub)+ `/boot/initramfs-linux.img`;无 `vmlinuz-*`,preset 只有 default
  - alarm 无 efifs(404)→ XBOOTLDR 在 alarm 下必须 FAT32
  - autodetect 在 qemu-user 下读到宿主 x86_64 /sys → 安装期临时移除、末尾恢复(备份文件法)
  - 包实测(2026-09-01):无 opencode/turbostat/yay(官方仓)/efifs;yay 由 archlinuxcn aarch64 提供(yay-13.0.0-1 实测)

---

### Task 1: 新建 distro/alarm.sh

**Files:**
- Create: `distro/alarm.sh`
- Test: `tests/run.sh`(新小节 21)

**Interfaces:**
- Consumes: `chroot_write_file`/`chroot_run`(lib/chroot.sh)、`log/die/warn`(lib/common.sh)、全局 `MNT_DIR`/`SCRIPT_DIR`/`MY_ALARM_MIRROR`
- Produces(后续任务依赖):
  - `distro_host_preflight()` — 主入口 `declare -F` 守卫调用;设全局 `PACSTRAP_CONF`
  - 全局 `PACSTRAP_CONF`(空=bootstrap 未生成;Task 3 的 base.sh 读取)
  - `distro_base_packages()` → echo 包列表(base.sh pacstrap 用)
  - `distro_setup_repos()` / `distro_kernel_packages()` / `distro_post_install()` — 主入口流程调用;`distro_kernel_packages` 设全局 `KERNEL_PKG=linux-aarch64`、`KERNEL_PKGS`

- [ ] **Step 1: 写失败测试**

tests/run.sh 第 309 行之前插入:

```bash
# ---- 21. alarm(aarch64)支持 ----
check "distro/alarm.sh 存在" "[[ -f distro/alarm.sh ]]"
check "alarm 定义四函数契约" "grep -q '^distro_base_packages()' distro/alarm.sh && grep -q '^distro_setup_repos()' distro/alarm.sh && grep -q '^distro_kernel_packages()' distro/alarm.sh && grep -q '^distro_post_install()' distro/alarm.sh"
check "alarm 定义 distro_host_preflight" "grep -q '^distro_host_preflight()' distro/alarm.sh"
check "alarm preflight 检查 binfmt qemu-aarch64" "grep -q 'binfmt_misc/qemu-aarch64' distro/alarm.sh"
check "alarm preflight 检查 F flag" "grep -q 'flags:.*F' distro/alarm.sh"
check "alarm 构建密钥指纹" "grep -q '68B3537F39A313B3E574D06777193F152BDBE6A6' distro/alarm.sh"
check "alarm base_packages 显式含 archlinuxarm-keyring" "grep -q 'archlinuxarm-keyring' distro/alarm.sh"
check "alarm base_packages 无 efifs(alarm 无此包)" "! grep -q efifs distro/alarm.sh"
check "alarm 数据库不签名 DatabaseOptional" "grep -q 'Required DatabaseOptional' distro/alarm.sh"
check "alarm 四仓库段 core/extra/alarm/aur" "grep -q '^\[alarm\]' distro/alarm.sh && grep -q '^\[aur\]' distro/alarm.sh"
check "alarm 内核包 linux-aarch64" "grep -q 'KERNEL_PKG=linux-aarch64' distro/alarm.sh"
check "alarm autodetect 备份恢复法" "grep -q 'mkinitcpio.conf.alarm-orig' distro/alarm.sh"
check "alarm 不做 pacman-key --init(pacstrap -K 已做)" "! grep -q 'pacman-key --init' distro/alarm.sh"
check "alarm 做 pacman-key --populate" "grep -q 'pacman-key --populate archlinuxarm' distro/alarm.sh"
check "alarm dtb override 到 /efi/dtb/base" "grep -q '/efi/dtb/base' distro/alarm.sh"
check "alarm 读 MY_ALARM_MIRROR" "grep -q 'MY_ALARM_MIRROR' distro/alarm.sh"
check "alarm 无 multilib(aarch64 无此概念)" "! grep -qi multilib distro/alarm.sh"
```

- [ ] **Step 2: 运行测试确认失败**

Run: `bash tests/run.sh 2>&1 | grep -c '^FAIL'` — 预期 17 项 FAIL(alarm 段全部)

- [ ] **Step 3: 实现 distro/alarm.sh**

完整文件内容:

```bash
#!/usr/bin/env bash
# distro/alarm.sh — Arch Linux ARM (aarch64) 实现
# 契约:distro_base_packages / distro_setup_repos / distro_kernel_packages /
# distro_post_install(同 arch.sh/cachyos.sh)+ 可选 distro_host_preflight
# (主入口 declare -F 守卫调用,dry-run 门后、动磁盘前)。
#
# 跨架构要点(依据 docs/superpowers/specs/2026-09-01-archlinuxarm-support-design.md §3):
# - pacstrap 无 --arch:跨架构 = pacstrap -C <bootstrap conf>(Architecture=aarch64)
#   + -M(不拷宿主 mirrorlist);-K 保留——pacstrap 源码实测(:208-218):-K 只对
#   目标 keyring 做 --init,安装期包验签走宿主 keyring(故 preflight 第 2 步
#   必须先把 alarm 构建密钥导入宿主 keyring)
# - alarm 仓库数据库不签名(上游设计,非镜像问题):SigLevel=Required DatabaseOptional
# - chroot 内 aarch64 二进制经 binfmt_misc(qemu-aarch64-static,F flag)执行
# - mkinitcpio autodetect 在 qemu-user 下读到的是宿主 x86_64 /sys,RK3588 专有
#   驱动进不了 initramfs(eMMC/SD 必死)→ 安装期临时移除、post_install 恢复。
#   恢复的原因:删 autodetect 不是 alarm 官方做法(其 mkinitcpio 包不 patch
#   mkinitcpio.conf),真机上的后续内核更新需要 autodetect 正确裁剪

# pacstrap 的自定义 pacman.conf 路径,由 distro_host_preflight 生成;
# modules/base.sh 读此变量,非空则追加 -C/-M
PACSTRAP_CONF=""

# alarm 构建密钥(签名所有 alarm 包;archlinuxarm 官方文档 + keyring 包核实)
_ALARM_BUILD_KEY=68B3537F39A313B3E574D06777193F152BDBE6A6

# 镜像地址:MY_ALARM_MIRROR 为空用 geo 默认;值含 $arch/$repo 占位符(此处转义)
_alarm_mirror() {
    echo "${MY_ALARM_MIRROR:-https://mirror.archlinuxarm.org/\$arch/\$repo}"
}

# alarm 四仓库段:bootstrap(Server= 直写)与目标内正式配置(Include mirrorlist)共用
_alarm_repo_sections() {
    local inc=$1
    cat <<EOF

[core]
$inc

[extra]
$inc

[alarm]
$inc

[aur]
$inc
EOF
}

distro_host_preflight() {
    # 1) binfmt_misc:qemu-aarch64 必须已注册、enabled、带 F flag(注册时打开
    #    解释器文件,chroot 内无需拷 qemu-aarch64-static;无 F 则 chroot 内
    #    执行 aarch64 二进制直接 Exec format error)
    local bf=/proc/sys/fs/binfmt_misc/qemu-aarch64
    [[ -f $bf ]] || die "binfmt_misc 未注册 qemu-aarch64 —— 宿主安装: sudo pacman -S qemu-user-static qemu-user-static-binfmt"
    [[ $(head -1 "$bf") == enabled ]] || die "binfmt qemu-aarch64 未 enabled(见 $bf)"
    grep -q '^flags:.*F' "$bf" \
        || die "binfmt qemu-aarch64 缺 F flag(fix_binary),chroot 内无法执行 aarch64 二进制"

    # 2) 宿主 keyring 导入 alarm 构建密钥(pacstrap 安装期验签走宿主 keyring;
    #    与 cachyos keyring 同手法。注意:这是对宿主 keyring 的持久改动,README 已写明)
    log "宿主 keyring 导入 alarm 构建密钥"
    pacman-key --recv-keys "$_ALARM_BUILD_KEY"
    pacman-key --lsign-key "$_ALARM_BUILD_KEY"

    # 3) bootstrap pacman.conf(pacstrap -C 用;临时文件统一放 .tmp/,不入库)
    mkdir -p "$SCRIPT_DIR/.tmp"
    PACSTRAP_CONF="$SCRIPT_DIR/.tmp/alarm-bootstrap-pacman.conf"
    log "生成 bootstrap pacman.conf: $PACSTRAP_CONF(mirror: $(_alarm_mirror))"
    {
        cat <<'EOF'
[options]
HoldPkg = pacman glibc
Architecture = aarch64
CheckSpace
# alarm 仓库数据库不签名是上游设计(非镜像问题)
SigLevel = Required DatabaseOptional
ParallelDownloads = 5
EOF
        _alarm_repo_sections "Server = $(_alarm_mirror)"
    } >"$PACSTRAP_CONF"
}

distro_base_packages() {
    # 无 efifs(alarm 仓库无此包,包页 404)→ XBOOTLDR 在 alarm 下是 FAT32,
    # systemd-boot 原生可读;btrfs-progs 必须在(内核安装触发 mkinitcpio 的
    # fsck hook,缺 btrfsck 非零退出,同 arch.sh 注释);archlinuxarm-keyring
    # 显式列入:distro_setup_repos 的 --populate 需要它提供的官方 keyring 文件,
    # 不赌 base 组的传递依赖
    echo "base archlinuxarm-keyring linux-firmware btrfs-progs iptables-nft"
}

distro_setup_repos() {
    # pacstrap 用的是 bootstrap conf(-C);目标内 /etc/pacman.conf 是 alarm
    # pacman 包出厂内容,覆写为确定形态(幂等;宿主侧直接写,同 pacman.sh:52 手法)
    log "alarm 仓库配置(mirror: $(_alarm_mirror))"
    chroot_write_file /etc/pacman.d/mirrorlist <<<"Server = $(_alarm_mirror)"
    {
        cat <<'EOF'
[options]
HoldPkg = pacman glibc
Architecture = aarch64
CheckSpace
SigLevel = Required DatabaseOptional
ParallelDownloads = 5
Color
UseSyslog
VerbosePkgLists
EOF
        _alarm_repo_sections "Include = /etc/pacman.d/mirrorlist"
    } >"$MNT_DIR/etc/pacman.conf"

    # keyring:--init 已由 pacstrap -K 完成(目标 keyring 已有本地 master key);
    # --populate 导入 archlinuxarm-keyring 包的官方 keyring(master×3 + 构建密钥)
    # 并 lsign。qemu-user 下 gpg 明显变慢(分钟级),属预期
    chroot_run pacman-key --populate archlinuxarm
    chroot_run pacman -Syu --noconfirm
}

distro_kernel_packages() {
    # 全局变量契约(主入口必须当前 shell 调用,子 shell 丢赋值);
    # linux-aarch64 产出 /boot/Image + /boot/initramfs-linux.img(无 vmlinuz-*)
    KERNEL_PKG=linux-aarch64
    KERNEL_PKGS="linux-aarch64 linux-aarch64-headers"

    # 临时移除 autodetect(原因见文件头注释;备份恢复法,不做双向 sed——
    # 二次字符串拼接太脆弱)。distro_post_install 负责恢复
    cp "$MNT_DIR/etc/mkinitcpio.conf" "$MNT_DIR/etc/mkinitcpio.conf.alarm-orig"
    sed -i 's/^\(HOOKS=.*\)autodetect /\1/' "$MNT_DIR/etc/mkinitcpio.conf"
    if grep '^HOOKS=' "$MNT_DIR/etc/mkinitcpio.conf" | grep -q autodetect; then
        die "mkinitcpio.conf 移除 autodetect 失败(HOOKS 行形态变化?)"
    fi
}

distro_post_install() {
    # 1) 恢复 autodetect:镜像内 initramfs 已是安装期生成的完整版;此后真机上的
    #    内核更新在真实 RK3588 硬件上跑 mkinitcpio,autodetect 正常裁剪。
    #    中间无其他模块改 mkinitcpio.conf(全仓 grep 核实),整文件恢复安全
    mv "$MNT_DIR/etc/mkinitcpio.conf.alarm-orig" "$MNT_DIR/etc/mkinitcpio.conf"

    # 2) DTB override 通道:内核包自带 dtb → edk2-rk3588 约定路径 /efi/dtb/base/
    #    (固件优先加载它再做 fix-up)。缺文件 warn 不 die:固件经 EFI config
    #    table 提供的内置 fix-up DTB 可兜底。引导项不写 devicetree 行——
    #    bootloader 侧覆盖会丢固件 fix-up
    local dtb="$MNT_DIR/boot/dtbs/rockchip/rk3588-orangepi-5-plus.dtb"
    if [[ -f $dtb ]]; then
        mkdir -p "$MNT_DIR/efi/dtb/base"
        cp "$dtb" "$MNT_DIR/efi/dtb/base/"
    else
        warn "内核包未带 rk3588-orangepi-5-plus.dtb,跳过 /efi/dtb override(固件内置 DTB 兜底)"
    fi
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `bash tests/run.sh 2>&1 | tail -2` — 预期失败 0(303+17=320 全过)

- [ ] **Step 5: Commit**

```bash
git add distro/alarm.sh tests/run.sh
git commit -m "feat(distro): 新增 distro/alarm.sh(Arch Linux ARM aarch64 后端)"
```

---

### Task 2: 主入口 arch-install 接线 alarm

**Files:**
- Modify: `arch-install`(usage :33、白名单 :97、CPUTYPE 段 :157-159、preflight 段 :167-169、末尾提示 :214-216)
- Test: `tests/run.sh`(小节 21 追加)

**Interfaces:**
- Consumes: Task 1 的 `distro_host_preflight`(经 `declare -F` 守卫,alarm.sh 未 source 时不炸)
- Produces: `DISTRO=alarm` 时 `CPUTYPE=generic`(lib/disk.sh install_bootloader 的 generic 逃逸口依赖,Task 5)

- [ ] **Step 1: 写失败测试**

tests/run.sh 小节 21 末尾追加:

```bash
check "--distro 白名单含 alarm" "grep -q 'DISTRO == alarm' arch-install"
check "alarm 强制 CPUTYPE=generic" "grep -q 'CPUTYPE=generic' arch-install"
check "主入口守卫调用 distro_host_preflight" "grep -q 'declare -F distro_host_preflight' arch-install"
check "alarm 镜像末尾提示 dd 而非 qemu-x86" "grep -q 'alarm(aarch64)镜像' arch-install"
check "dry-run alarm" "./arch-install --target /tmp/x.img --profile server --distro alarm --dry-run >/dev/null 2>&1"
```

- [ ] **Step 2: 运行确认失败**

Run: `bash tests/run.sh 2>&1 | grep '^FAIL'` — 预期新增 5 项 FAIL

- [ ] **Step 3: 实现**

四处修改:

1. usage(:33):`-distro NAME          arch | cachyos(默认 arch)` 改为:

```bash
  --distro NAME          arch | cachyos | alarm(默认 arch;alarm=Arch Linux ARM aarch64)
```

2. 白名单(:97)改为:

```bash
    [[ $DISTRO == arch || $DISTRO == cachyos || $DISTRO == alarm ]] || die "未知 distro: $DISTRO"
```

3. CPUTYPE 段(:157 注释与 :159 之间)插入:

```bash
    # alarm(aarch64)没有 amd/intel 微码概念:强制 generic,跳过
    # detect_cputype(/sys 解析只对 x86 有意义)与后续 $CPUTYPE-ucode 安装;
    # lib/disk.sh 引导项的 generic 逃逸口已有
    [[ $DISTRO == alarm ]] && CPUTYPE=generic
```

4. preflight 段(:169 `declare -F _cachyos_preflight_emulation ...` 之后)追加:

```bash
    # distro 级宿主机预检(仅 alarm 定义):binfmt_misc 注册检查 +
    # alarm 构建密钥导入宿主 keyring + 生成 bootstrap pacman.conf
    declare -F distro_host_preflight &>/dev/null && distro_host_preflight
```

5. 末尾镜像提示(:214-216)改为:

```bash
    if [[ $TARGET_TYPE == image ]]; then
        if [[ $DISTRO == alarm ]]; then
            info "alarm(aarch64)镜像不能用 qemu-system-x86_64 验证:dd 到 SD/eMMC/NVMe 上真机启动(需 edk2 固件;目标介质不得残留 U-Boot)"
        else
            info "qemu 验证: qemu-system-x86_64 -m 4G -bios /usr/share/ovmf/x64/OVMF.4m.fd -drive file=$TARGET,format=raw"
        fi
    fi
```

- [ ] **Step 4: 运行确认通过**

Run: `bash tests/run.sh 2>&1 | tail -2` — 预期 0 失败(dry-run alarm 不需要 root 也不需要 binfmt:preflight 在 dry-run 门之后)

- [ ] **Step 5: Commit**

```bash
git add arch-install tests/run.sh
git commit -m "feat(main): --distro 接入 alarm(aarch64)— 白名单/CPUTYPE=generic/host_preflight 钩子"
```

---

### Task 3: modules/base.sh pacstrap -C/-M 参数化

**Files:**
- Modify: `modules/base.sh:6-9`
- Test: `tests/run.sh`(小节 21 追加)

**Interfaces:**
- Consumes: Task 1 的全局 `PACSTRAP_CONF`(x86 distro 不设,默认为空 → 行为不变)

- [ ] **Step 1: 写失败测试**

```bash
check "base.sh 支持 PACSTRAP_CONF(-C/-M)" "grep -q 'PACSTRAP_CONF' modules/base.sh"
check "pacstrap -K 保留不变" "grep -q 'pacstrap_args=(-K)' modules/base.sh"
```

- [ ] **Step 2: 运行确认失败**(新增 2 项 FAIL)

- [ ] **Step 3: 实现**

`mod_install()` 开头的 pacstrap 调用(:7-9)改为:

```bash
    log "pacstrap 基础系统"
    # alarm(aarch64)跨架构:pacstrap 无 --arch,用 -C 指定 bootstrap pacman.conf
    # (Architecture=aarch64,由 distro/alarm.sh 的 host_preflight 生成)+ -M
    # 跳过宿主 mirrorlist 拷贝;-K 不变(pacstrap 源码:安装期验签走宿主
    # keyring,-K 只对目标 keyring 做 --init)
    local -a pacstrap_args=(-K)
    [[ -n ${PACSTRAP_CONF:-} ]] && pacstrap_args+=(-C "$PACSTRAP_CONF" -M)
    # shellcheck disable=SC2046
    pacstrap "${pacstrap_args[@]}" "$MNT_DIR" $(distro_base_packages)
```

- [ ] **Step 4: 运行确认通过**

- [ ] **Step 5: Commit**

```bash
git add modules/base.sh tests/run.sh
git commit -m "feat(base): pacstrap 支持 distro 自定义 conf(PACSTRAP_CONF,-C/-M;alarm 跨架构用)"
```

---

### Task 4: lib/disk.sh 根分区 GUID 按架构 + XBOOTLDR FAT32

**Files:**
- Modify: `lib/disk.sh`(`partition_and_mount` :79-93)、`modules/growfs.sh`(仅注释)
- Test: `tests/run.sh`(小节 21 追加)

**Interfaces:**
- Consumes: 全局 `DISTRO`(主入口已解析)
- Produces: alarm 镜像的根分区 GUID=B921B045-1DF0-41C3-AF44-4C6F280D3FAE("Linux root (ARM-64)");systemd-repart `Type=root` 按架构自动匹配,`modules/growfs.sh` 无需代码改动

- [ ] **Step 1: 写失败测试**

```bash
check "根分区 GUID 按架构(ARM-64 DPS)" "grep -q 'B921B045-1DF0-41C3-AF44-4C6F280D3FAE' lib/disk.sh"
check "alarm XBOOTLDR 用 FAT32(无 efifs)" "grep -q 'mkfs.fat -n \"Linux Boot\"' lib/disk.sh"
check "x86 XBOOTLDR 仍是 ext4" "grep -q 'mkfs.ext4 -F -L \"Linux Boot\"' lib/disk.sh"
```

- [ ] **Step 2: 运行确认失败**(新增 2 项 FAIL;第 3 条现存即过)

- [ ] **Step 3: 实现**

1. `partition_and_mount` 的 sfdisk 段(:79-86)改为:

```bash
    log "分区: $dev"
    # 根分区 GUID 按架构(Discoverable Partitions Spec):aarch64 用
    # "Linux root (ARM-64)";systemd-repart 的 Type=root 按架构自动匹配,
    # modules/growfs.sh 无需跟着变
    local root_guid=4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709 root_name="Linux root (x86-64)"
    if [[ $DISTRO == alarm ]]; then
        root_guid=B921B045-1DF0-41C3-AF44-4C6F280D3FAE
        root_name="Linux root (ARM-64)"
    fi
    sfdisk --no-reread "$dev" <<_EOF_
label: gpt
unit: sectors
size=256MiB, name="EFI System", type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B
size=1GiB, name="Linux extended boot", attrs="LegacyBIOSBootable", type=BC13C2FF-59E6-4262-A352-B275FD6F7172
name="$root_name", type=$root_guid
_EOF_
```

2. 格式化段(:92 `mkfs.ext4` 行)改为:

```bash
    # XBOOTLDR:alarm 仓库无 efifs(包页 404),systemd-boot 在 aarch64 只能读
    # FAT32 → alarm 下 /boot 用 FAT32;x86 维持 ext4(efifs 驱动复制段对 alarm
    # 自然跳过:目录不存在)
    if [[ $DISTRO == alarm ]]; then
        mkfs.fat -n "Linux Boot" -F 32 "$PART_XBOOT" >/dev/null
    else
        mkfs.ext4 -F -L "Linux Boot" "$PART_XBOOT" >/dev/null
    fi
```

3. `modules/growfs.sh`:找到写 `/etc/repart.d/50-root.conf` 的注释,把其中关于
   `Type=root` 的说明补一句"(按架构自动解析:x86-64↔4F68…、ARM-64↔B921…,
   lib/disk.sh 分区 GUID 同口径)"。只改注释,不改代码。

- [ ] **Step 4: 运行确认通过**

- [ ] **Step 5: Commit**

```bash
git add lib/disk.sh modules/growfs.sh tests/run.sh
git commit -m "feat(disk): 根分区 GUID 按架构(DPS ARM-64)+ alarm XBOOTLDR 改 FAT32(无 efifs)"
```

---

### Task 5: install_bootloader alarm 引导项分支

**Files:**
- Modify: `lib/disk.sh`(`install_bootloader` :139-167)
- Test: `tests/run.sh`(小节 21 追加)

**Interfaces:**
- Consumes: 全局 `DISTRO`、`KERNEL_PKG`(alarm=linux-aarch64)、`CPUTYPE`(alarm 时 Task 2 已强制 generic → ucode_line 自动为空)、`MY_KERNEL_PARAMS`
- Produces: alarm 引导项 `/boot/loader/entries/alarm.conf`,内容 `linux /Image` + `initrd /initramfs-linux.img`,无 ucode/devicetree/add_efi_memmap

- [ ] **Step 1: 写失败测试**

```bash
check "alarm 引导项用 /Image(PE-stub;Image.gz 不可加载)" "grep -q 'linux   /Image' lib/disk.sh"
check "alarm 引导项 initramfs-linux.img" "grep -q 'initrd  /initramfs-linux.img' lib/disk.sh"
check "alarm 引导项标题 Arch Linux ARM" "grep -q 'Arch Linux ARM' lib/disk.sh"
check "alarm 引导项无 add_efi_memmap(x86-only)" "! awk '/DISTRO.*== alarm.*\)/,/^    else/' lib/disk.sh | grep -q add_efi_memmap"
```

- [ ] **Step 2: 运行确认失败**(前 3 项 FAIL)

- [ ] **Step 3: 实现**

`install_bootloader` 的命名与条目段(:139-167)重构为:

```bash
    # 引导项按发行版命名:CachyOS 内核包 linux-cachyos[-变体] 产生
    # /boot/vmlinuz-linux-cachyos[-变体] 与 initramfs-linux-cachyos[-变体][-fallback].img;
    # alarm 的 linux-aarch64 产生 /boot/Image 与 initramfs-linux.img,三者不能复用
    local name title
    case ${DISTRO:-arch} in
        cachyos) name=cachyos; title="CachyOS" ;;
        alarm)   name=alarm;   title="Arch Linux ARM" ;;
        *)       name=arch;    title="Arch Linux" ;;
    esac
    mkdir -p "$MNT_DIR"/boot/loader/entries/
    # MY_KERNEL_PARAMS:追加的自定义内核参数(如 ttm.pages_limit 调 GTT,见 config.example.sh)
    local kparams=""
    [[ -n ${MY_KERNEL_PARAMS:-} ]] && kparams=" $MY_KERNEL_PARAMS"
    if [[ ${DISTRO:-arch} == alarm ]]; then
        # alarm linux-aarch64:/boot/Image 是 PE-stub(UEFI 可直接加载;Image.gz
        # 是 gzip 包裹,systemd-boot LoadImage 不支持);initramfs 固定
        # initramfs-linux.img(preset 仅 PRESETS=('default'),无 fallback);
        # 无微码(CPUTYPE=generic → ucode_line 为空);不写 devicetree 行——
        # edk2-rk3588 经 EFI config table 提供带 fix-up 的 DTB,bootloader 侧
        # 覆盖会丢 fix-up;add_efi_memmap 是 x86-only 参数
        cat >"$MNT_DIR"/boot/loader/entries/$name.conf <<EOF
title   $title
linux   /Image
initrd  /initramfs-linux.img
options root=UUID=$uuid rootfstype=btrfs rootflags=subvol=/ArchLinux mitigations=off rw$kparams
EOF
    else
        cat >"$MNT_DIR"/boot/loader/entries/$name.conf <<EOF
title   $title
linux   /vmlinuz-$KERNEL_PKG
$ucode_line
initrd  /initramfs-$KERNEL_PKG.img
options root=UUID=$uuid rootfstype=btrfs rootflags=subvol=/ArchLinux mitigations=off add_efi_memmap rw$kparams
EOF
        # fallback 条目只在对应 initramfs 存在时写:CachyOS 内核 preset 只有
        # default(实测无 initramfs-*-fallback.img,cachyos-hooks 包也不提供 preset),
        # 写了会是指向不存在文件的坏条目;Arch 官方内核 preset 有 fallback,正常生成
        if [[ -f $MNT_DIR/boot/initramfs-$KERNEL_PKG-fallback.img ]]; then
            cat >"$MNT_DIR"/boot/loader/entries/$name-fallback.conf <<EOF
title   $title (fallback initramfs)
linux   /vmlinuz-$KERNEL_PKG
$ucode_line
initrd  /initramfs-$KERNEL_PKG-fallback.img
options root=UUID=$uuid rootfstype=btrfs rootflags=subvol=/ArchLinux mitigations=off add_efi_memmap rw$kparams
EOF
        fi
    fi
```

- [ ] **Step 4: 运行确认通过**(现有 arch/cachyos 相关断言不受影响)

- [ ] **Step 5: Commit**

```bash
git add lib/disk.sh tests/run.sh
git commit -m "feat(disk): install_bootloader alarm 分支(/Image + initramfs-linux.img,无 ucode/devicetree/add_efi_memmap)"
```

---

### Task 6: 模块门禁(hardware turbostat / dev-tools opencode / pacman mirrorlist 跳过)

**Files:**
- Modify: `modules/hardware.sh:5-7`、`modules/dev-tools.sh:5-10`、`modules/pacman.sh:14-38`
- Test: `tests/run.sh`(小节 21 追加)

**Interfaces:**
- Consumes: 全局 `DISTRO`;包可用性事实(Global Constraints 已列)
- Produces: server profile 全模块在 alarm 下可装

- [ ] **Step 1: 写失败测试**

```bash
check "hardware turbostat 有 alarm 门禁(x86-only)" "grep -q 'pkgs+=(turbostat)' modules/hardware.sh"
check "dev-tools opencode 有 alarm 门禁(alarm 404)" "grep -q 'pkgs+=(opencode)' modules/dev-tools.sh"
check "pacman mirrorlist 四模式跳过 alarm" "grep -q 'DISTRO:-arch} != alarm' modules/pacman.sh"
check "pacman archlinuxcn 段保留(cn 有 aarch64 仓)" "grep -q 'archlinuxcn-keyring' modules/pacman.sh"
check "cli-tools yay 保留(cn aarch64 提供)" "grep -qw yay modules/cli-tools.sh"
```

- [ ] **Step 2: 运行确认失败**(前 3 项 FAIL,后 2 项现存即过)

- [ ] **Step 3: 实现**

1. `modules/hardware.sh` 的 pacman_install 段(:6-7)改为:

```bash
    # turbostat 是 x86-only(Intel/AMD PMU,alarm 包页 404),alarm(aarch64)跳过;
    # linux-tools-meta 在 alarm 存在(2026-09-01 实测 200),保留
    local pkgs=(lm_sensors linux-tools-meta htop hwloc
        smartmontools nvme-cli dmidecode cpupower irqbalance)
    [[ ${DISTRO:-arch} == alarm ]] || pkgs+=(turbostat)
    pacman_install "${pkgs[@]}"
```

2. `modules/dev-tools.sh` 第一批装包(:7-10)改为:

```bash
    # 无 wakatime:官方仓库没有(仅 AUR 有 wakatime-cli),本安装器不用 AUR
    # opencode 在 alarm(aarch64)仓库不存在(包页 404),alarm 跳过
    local pkgs=(git git-delta github-cli \
        neovim vim cmake shellcheck \
        python-black patch parallel)
    [[ ${DISTRO:-arch} == alarm ]] || pkgs+=(opencode)
    pacman_install "${pkgs[@]}"
```

3. `modules/pacman.sh` 的 mirrorlist 段(:14-38)整体包一层门禁(case 块不动):

```bash
    # alarm 的 mirror 由 distro/alarm.sh 的 distro_setup_repos 写入
    # (MY_ALARM_MIRROR);x86 的四种 mirrorlist 模式对 alarm 无意义
    if [[ ${DISTRO:-arch} != alarm ]]; then
    log "mirrorlist: $MIRRORLIST"
    case $MIRRORLIST in
        ...原 case 块整体内移一级缩进...
    esac
    fi
```

(archlinuxcn 段 :40 起**不动**:`Server = https://repo.archlinuxcn.org/$arch` 自动展开 aarch64,cn 有该仓。)

- [ ] **Step 4: 运行确认通过**

- [ ] **Step 5: Commit**

```bash
git add modules/hardware.sh modules/dev-tools.sh modules/pacman.sh tests/run.sh
git commit -m "feat(modules): alarm 门禁 — hardware 跳 turbostat、dev-tools 跳 opencode、pacman mirrorlist 交还 distro"
```

---

### Task 7: 配置模板 + 设备预设 + .gitignore

**Files:**
- Modify: `config/config.example.sh`(末尾追加)、`devices/example.sh`、`.gitignore`
- Create: `devices/opi5plus.sh`(gitignored,**不 commit**)
- Test: `tests/run.sh`(小节 21 追加)

**Interfaces:**
- Produces: `MY_ALARM_MIRROR`(distro/alarm.sh 的 `_alarm_mirror` 消费)

- [ ] **Step 1: 写失败测试**

```bash
check "config 模板含 MY_ALARM_MIRROR" "grep -q MY_ALARM_MIRROR config/config.example.sh"
check "devices 模板含 alarm 示例" "grep -q 'DISTRO=alarm' devices/example.sh"
check ".gitignore 含 .tmp(bootstrap conf 临时目录)" "grep -q '^\.tmp' .gitignore"
```

- [ ] **Step 2: 运行确认失败**(3 项 FAIL)

- [ ] **Step 3: 实现**

1. `config/config.example.sh` 末尾追加:

```bash
# ---- Arch Linux ARM(仅 --distro alarm)----
MY_ALARM_MIRROR=""                # alarm 镜像;空=geo 默认 mirror.archlinuxarm.org。
                                  # 中国大陆建议 https://mirrors.ustc.edu.cn/archlinuxarm/$arch/$repo
```

2. `devices/example.sh` 的 `#DISTRO=cachyos` 行(:15)上方/下方加 alarm 示例:

```bash
#DISTRO=alarm                     # arch | cachyos | alarm(Arch Linux ARM aarch64)
#  alarm 设备常见配套(以 RK3588/OPi5+ 为例):
#MY_ALARM_MIRROR="https://mirrors.ustc.edu.cn/archlinuxarm/\$arch/\$repo"
#SKIP_MODULES=mem-zswap           # 内存方案改 zram(不建 swapfile)
#EXTRA_MODULES=mem-zram
#MY_KERNEL_PARAMS="console=ttyS2,1500000"   # RK3588 串口 console(按设备改)
```

3. `.gitignore` 加一行 `.tmp/`(先读现有内容确认没有)。

4. 创建 `devices/opi5plus.sh`(**gitignored,不要 git add**):

```bash
#!/usr/bin/env bash
# devices/opi5plus.sh — Orange Pi 5 Plus(RK3588,SPI 已刷 edk2-rk3588,UEFI)
DISTRO=alarm
MY_HOSTNAME=opi5plus
# 内存:zram(不建 swapfile;--skip/--extra 对设备默认是整体覆盖)
SKIP_MODULES=mem-zswap
EXTRA_MODULES=mem-zram
# 串口 console(edk2 同串口,1500000n8)
MY_KERNEL_PARAMS="console=ttyS2,1500000"
MY_ALARM_MIRROR="https://mirrors.ustc.edu.cn/archlinuxarm/\$arch/\$repo"
SIZE=8G
```

- [ ] **Step 4: 运行确认通过**

- [ ] **Step 5: Commit(只提交 tracked 文件)**

```bash
git add config/config.example.sh devices/example.sh .gitignore
git commit -m "feat(config): MY_ALARM_MIRROR + devices 模板 alarm 示例 + .gitignore .tmp/"
# 确认 devices/opi5plus.sh 未被提交:
git status --short devices/
```

---

### Task 8: 文档同步(README×2 + AGENTS.md + CHANGELOG)

**Files:**
- Modify: `README.md`、`README.zh-CN.md`、`AGENTS.md`

- [ ] **Step 1: README.md**

- Features 的 "Two distros" 条改为三个,加 alarm 说明(Arch Linux ARM aarch64,server profile only,需宿主 qemu-user-static{,-binfmt} + binfmt F flag;宿主 keyring 会被导入 alarm 构建密钥 68B3…,属持久改动)
- Usage 加一行示例:`sudo ./arch-install --device opi5plus --target opi5plus.img --profile server`
- Layout 的 `distro/` 行加 alarm.sh
- Module overview 附近加一句:alarm 下 hardware 不装 turbostat、dev-tools 不装 opencode、yay 来自 archlinuxcn aarch64
- 明确写:alarm 当前仅验证 server profile;镜像 dd 到 SD/eMMC/NVMe 真机启动(edk2 固件,介质不得残留 U-Boot),不能用 qemu-system-x86_64 验证

- [ ] **Step 2: README.zh-CN.md** — 同内容中文同步

- [ ] **Step 3: AGENTS.md**

- 目录结构 `distro/` 部分加一行:`distro/alarm.sh  Arch Linux ARM(aarch64):bootstrap conf、keyring populate、autodetect 临时移除/恢复、dtb override`
- CHANGELOG 顶部加条目(沿用现有详细风格),要点:新增 --distro alarm;distro/alarm.sh 四函数 + host_preflight;pacstrap -C/-M;GUID 按架构;XBOOTLDR FAT32(efifs 404);引导项 /Image;autodetect 备份恢复法(alarm 官方不删,真机更新要用);模块门禁 turbostat/opencode;archlinuxcn/yay 保留(cn aarch64);devices/opi5plus.sh;调研与方案见 docs/superpowers/specs/2026-09-01-archlinuxarm-support-design.md;tests 新增 N 项(以实际为准)
- TODO 区不动(alarm 支持落地后可加 "[x] archlinuxarm(aarch64)support" 行)

- [ ] **Step 4: Commit**

```bash
git add README.md README.zh-CN.md AGENTS.md
git commit -m "docs: alarm(aarch64)支持 — README×2、AGENTS.md 目录结构 + CHANGELOG"
```

---

### Task 9: 全量验证 + 镜像构建 + 真机验收(需用户协作)

**Files:** 无新文件;验证与实机构建

- [ ] **Step 1: 静态全绿**

```bash
bash tests/run.sh          # 全部通过(含既有 303 项回归)
shellcheck arch-install lib/*.sh distro/*.sh modules/*.sh  # 改动文件零新增告警
```

- [ ] **Step 2: dry-run 三 distro**

```bash
./arch-install --target /tmp/x.img --profile server --distro alarm --dry-run
./arch-install --target /tmp/x.img --profile server --distro arch --dry-run
./arch-install --target /tmp/x.img --profile server --distro cachyos --dry-run
```

- [ ] **Step 3: 构建 alarm 镜像(需要 root + 宿主已装 qemu-user-static qemu-user-static-binfmt)**

worktree 没有 gitignored 的 `config/config.sh`(从主 checkout 复制):
`cp ../../config/config.sh config/`(注意核对其中 MY_* 适用于本机构建)

```bash
sudo ./arch-install --device opi5plus --target .tmp/opi5plus.img --profile server
```

预期:pacstrap 走 -C bootstrap conf;pacman-key --populate 成功;mkinitcpio -P 产出 /boot/initramfs-linux.img;bootctl 装好 systemd-bootaa64.efi;/boot/loader/entries/alarm.conf 内容正确;/efi/dtb/base/rk3588-orangepi-5-plus.dtb 存在。

- [ ] **Step 4: 镜像检查(宿主侧,不启动)**

构建完成后手动 loop 挂载抽查:entries/alarm.conf 无 ucode 行、无 add_efi_memmap、含 `console=ttyS2,1500000`;`/etc/mkinitcpio.conf` 的 HOOKS **含** autodetect(已恢复);`/etc/fstab` 根行有 x-systemd.growfs。

- [ ] **Step 5: 真机验收(用户执行,spec §7.3 清单)**

dd 到 SD/eMMC/NVMe → OPi5+ 启动,核对:systemd-boot 可见并进入系统;`systemctl --failed` 空;repart+growfs 扩满;SSH 通;zram0 zstd;zswap=N;双网卡在;`uname -m`=aarch64;串口 ttyS2 有输出。

- [ ] **Step 6: 真机踩坑修复(如有)→ 补测试 → commit;全部通过后询问用户是否 merge master + push**

---

## Self-Review 记录

- Spec 覆盖:§5.2→Task 1/3;§5.3→Task 2;§5.4→Task 4/5;§5.6→Task 6;§5.7→Task 7;§6 错误处理→各任务 die 分支已含;§7 测试→各任务 Step 1 + Task 9;§10 文档→Task 8。§4 分区方案→Task 4/5。
- 占位符扫描:Task 6 Step 3.3 的 "原 case 块整体内移" 是对既有代码的机械缩进,非占位符;Task 8 README 文案由执行者按要点成文(文档写作,无代码占位)。
- 一致性:PACSTRAP_CONF(Task 1 产出 → Task 3 消费)、CPUTYPE=generic(Task 2 → Task 5)、mkinitcpio.conf.alarm-orig(Task 1 内自洽)、MY_ALARM_MIRROR(Task 7 → Task 1 的 _alarm_mirror)命名一致。
