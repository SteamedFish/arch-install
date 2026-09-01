# Arch Linux ARM (alarm) 支持设计 — RK3588 / Orange Pi 5 Plus

日期:2026-09-01
分支:feat/alarm-aarch64
状态:待用户审阅

## 1. 背景与目标

arch-install 目前仅支持 x86_64 的 Arch / CachyOS。本设计为其增加第三个
distro 后端 `alarm`(Arch Linux ARM, aarch64),首要目标设备为
Orange Pi 5 Plus(RK3588,SPI 已刷 edk2-rk3588,提供完整 UEFI 环境),
在 x86_64 构建宿主机上产出可 dd 的磁盘镜像,dd 到 SD/eMMC/NVMe 后直接
启动,使用 mainline 内核(alarm `linux-aarch64` 包,当前 7.2.2)。

成功标准:镜像 dd 到真机启动后 —— systemd-boot 引导项可见、根文件系统
repart+growfs 扩到盘满、无 failed units、SSH 可登录、双 RTL8125 网卡可用、
zram 生效。验收方式:只做真机实测,不做 qemu aarch64 模拟。

## 2. 范围

**In scope:**
- `distro/alarm.sh` 新 distro 后端(四函数契约 + 宿主机预检)
- 主入口 / lib 层的架构泛化(--distro 白名单、CPUTYPE、分区 GUID、
  XBOOTLDR 文件系统、引导项命名、binfmt 检查)
- server profile 在 aarch64 全链路网通(含模块门禁调整)
- `devices/opi5plus.sh` 设备预设(gitignored)+ 模板更新
- tests/run.sh 断言 + 真机验证

**Out of scope(明确不做):**
- desktop profile 在 aarch64(desktop-kde/desktop-niri 未验证)
- gpu-amd/gpu-nvidia/gpu-intel/gpu-mali/gpgpu/zfs/gaming 在 aarch64
- CachyOS aarch64(不存在该发行版)
- U-Boot/非 UEFI 路径、root on zfs
- efifs 移植(alarm 无此包,见 §4)

## 3. 调研结论(事实清单,均经源头核实)

### 3.1 跨架构 bootstrap
- `pacstrap` 任何版本都没有 `--arch`。跨架构做法是
  `pacstrap -C <自定义 pacman.conf> -M`(自定义 conf 里写
  `Architecture = aarch64`,-M 跳过宿主 mirrorlist 拷贝)。
- Arch Linux ARM 软件仓库**数据库不签名**(上游设计如此,非镜像问题),
  pacman.conf 需要 `SigLevel = Required DatabaseOptional`。
- alarm keyring:master keys 指纹
  `02922214DE8981D14DC2ACABBC704E86B823CD25` /
  `9D22B7BB678DC056B1F7723CB55C5315DCD9EE1A` /
  `69DD6C8FD314223E14362848BF7EEF7A9C6B5765`;
  构建密钥(签名所有包)`68B3537F39A313B3E574D06777193F152BDBE6A6`。
  `archlinuxarm-keyring` 是 any 架构包,随 alarm base 组进入 pacstrap。
- 宿主 pacman 验证 alarm 包前,需先在宿主 keyring
  `pacman-key --recv-keys` + `--lsign-key` 构建密钥
  (与 cachyos.sh 既有手法相同)。**这是对宿主 keyring 的持久改动,README
  需写明。**
- chroot 执行 aarch64 二进制依赖 binfmt_misc:宿主需安装
  `qemu-user-static` + `qemu-user-static-binfmt`
  (`/usr/lib/binfmt.d/qemu-aarch64-static.conf` 带 **F flag**,注册时
  打开解释器文件,chroot 内无需拷贝 qemu-aarch64-static)。
  arch-chroot 在 qemu-user 下可用(宿主侧 bind-mount /proc /sys /dev);
  gpg/pacman-key 在模拟下明显变慢,属预期。

### 3.2 内核与镜像内文件
- `linux-aarch64` 是 alarm 的 mainline 多平台内核。安装产出
  `/boot/Image`、`/boot/Image.gz`、`/boot/dtbs/<soc>/...dtb`
  (含 `rockchip/rk3588-orangepi-5-plus.dtb`)。**没有 `vmlinuz-*`**。
- mkinitcpio preset:`/etc/mkinitcpio.d/linux-aarch64.preset` 只有
  `PRESETS=('default')`,initramfs 文件名为
  `/boot/initramfs-linux.img`(注意:不是 `-linux-aarch64`)。
  现仓库 install_bootloader 已按 initramfs 文件存在性写 fallback 条目,
  无 fallback 文件自然不写。
- OPi5+ 的 mainline DTS 自内核 6.7 起存在
  (commit `236d225e1ee72a28aa7c2b1e39894e4390bbf51c`,2023-10)。
- arm64 的 `Image` 是 PE-stub(UEFI 可直接加载),`Image.gz` 是 gzip
  包裹——systemd-boot 的 LoadImage 路径**不能**加载 gzip 内核,引导项
  必须用未压缩的 `/Image`。

### 3.3 edk2-rk3588 固件行为(决定 DTB 策略)
- OPi5+ 是 Platinum 支持级别;**Mainline 模式默认启用**;官方建议内核
  ≥6.10,显示输出需 ≥6.15(当前 7.2 满足)。
- 固件通过 EFI configuration table 向 OS 提供**带 fix-up 的 DTB**
  (自动适配 PCIe/SATA/USB 配置)。因此 systemd-boot 引导项**不需要**
  `devicetree` 行——bootloader 侧覆盖反而会丢失固件 fix-up。
- 固件级 DTB override:把 dtb 放到 ESP 的 `\dtb\` / `\dtb\base\` /
  `\dtb\soc\` 目录(文件名如 `rk3588-orangepi-5-plus.dtb`),固件优先
  加载它再做 fix-up(固件能读 FAT32 和 ext4)。overlays 放
  `\dtb\overlays\`。
- 镜像前 32MiB 空白布局与现仓库分区(ESP 从 1MiB 起)无冲突;要求
  SPI/SD/eMMC 上**没有残留 U-Boot**(刷机须知,写 README)。

### 3.4 systemd-boot on aa64 / 文件系统约束
- systemd-boot 是 aa64 一等公民,`bootctl install` 在 aarch64 安装
  `systemd-bootaa64.efi`,BLS 规范一致。bootctl 在 qemu 模拟的 chroot
  里可运行。
- **alarm 仓库没有 efifs 包**(官方包页 404)。现仓库 x86 布局依赖 efifs
  让 systemd-boot 读 ext4 XBOOTLDR;aarch64 上 systemd-boot 只能读
  FAT32。→ 直接决定 §4 的分区方案。

### 3.5 mkinitcpio autodetect 在 qemu-user 下不可信(关键坑)
- qemu chroot 里 `/sys` 是宿主 x86_64 的,autodetect 按宿主硬件裁剪
  initramfs。RK3588 专有驱动(sdhci-of-arasan、phy-rockchip-*、
  pcie-rockchip-host 等)不会进入 initramfs → **eMMC/SD 启动必死**;
  NVMe 碰巧可能因宿主也是 NVMe 而同名命中,但不可依赖。
- 对策:**安装期**从 `mkinitcpio.conf` 的 HOOKS 中临时删除 autodetect
  (完整 initramfs,体积变大可接受),**安装末尾恢复**(见 §5.2)——
  镜像内首启用的是完整 initramfs;后续真机上的内核更新在真实 RK3588
  硬件上重新生成,autodetect 正常工作、产出裁剪合理的 initramfs。
- 上游事实(archlinuxarm/PKGBUILDs 核实):**删除 autodetect 不是 alarm
  官方做法**。alarm 的 `core/mkinitcpio` 包(41.1-1,arch=any)只有三个
  patch(默认 gzip 压缩 / gzip 内核 kver_gen / ALARM 内核 post hooks),
  均不触碰 `mkinitcpio.conf`,即 alarm 出厂 HOOKS 与 x86 Arch 相同、
  含 autodetect——官方构建跑在真实 ARM 硬件上,没有我们这种跨架构
  /sys 失真问题。另:`linux-aarch64` preset 确认为
  `PRESETS=('default')` 单预设(虽定义了 fallback_image 与
  `fallback_options="-S autodetect"` 但不构建)。

### 3.6 OPi5+ 硬件与 cmdline(mainline dts 实证)
- 双 2.5G 网口均为 PCIe 挂接 RTL8125(pcie2x1l1=右口,l2=左口),
  不是 GMAC;NVMe 走 pcie3x4(PCIe 3.0 x4);eMMC hs400 + SD + SPI NOR。
- `stdout-path = serial2:1500000n8` → 设备预设建议
  `MY_KERNEL_PARAMS="console=ttyS2,1500000"`。其余无需特殊 cmdline。

### 3.7 包可用性(archlinuxarm.org/packages/aarch64/ 实测)
| 有 | 无 |
|---|---|
| biome 2.3.14, ruff 0.15.20, uv 0.11.30 | opencode (404) |
| gopls 0.23.0, rust-analyzer 20260608 | efifs (404) |
| lua-language-server, bash-language-server, iptables-nft, zram-generator | turbostat(x86-only) |

- `yay`、`yaml-language-server` 当时未确认,实施时核实;yay 由
  archlinuxcn aarch64 提供(用户确认 archlinuxcn 支持 archlinuxarm,
  `Server = https://repo.archlinuxcn.org/$arch` 的 `$arch` 自动展开为
  aarch64,无需改动)。

## 4. 分区与引导方案(已定:方案 A)

保留现有三分区布局:**ESP /efi(fat32,256MiB)+ XBOOTLDR /boot + btrfs 根**;
aarch64 时 **/boot 从 ext4 改为 FAT32**(因无 efifs,systemd-boot 只能读
FAT32;内核 Image/initramfs/dtbs 都在 /boot,bootctl 直接可见)。

被否决的备选:
- **B: aarch64 用 GRUB arm64** —— 引入第二套 bootloader 链路,
  modules/zfs.sh 里还有针对 systemd-boot 的 growfs/mkinitcpio 假设,
  维护面翻倍。
- **C: 单 ESP(合并 /boot 进 /efi)** —— 破坏 x86/aarch64 布局一致性,
  ESP 体积膨胀,与 edk2 的 dtb override 目录约定(`/efi/dtb/`)耦合过深。

DTB 策略:默认用固件经 config table 提供的 fix-up DTB(引导项无
devicetree 行);`distro_post_install` 额外把内核包自带的
`rk3588-orangepi-5-plus.dtb` 复制到 `/efi/dtb/base/`,作为"内核 DTB
领先固件修复"时的 override 通道(edk2 约定路径)。不需要时删掉该文件
即回落固件内置。

## 5. 详细设计

### 5.1 distro 接口契约(回顾)

每个 distro 文件提供四个函数,`KERNEL_PKG`/`KERNEL_PKGS` 为全局变量
契约(子 shell 会丢赋值,主入口必须当前 shell 调用
distro_kernel_packages)。另外支持可选函数 `distro_host_preflight`
(若声明则主入口在 dry-run 门后调用,同 _cachyos_preflight_emulation
的 `declare -F` 守卫模式)。

### 5.2 新文件 distro/alarm.sh

- `distro_host_preflight()`(可选契约,新增):
  1. 检查 `/proc/sys/fs/binfmt_misc/qemu-aarch64` 已注册且带 F flag,
     否则 die 并提示安装 qemu-user-static{,-binfmt};
  2. 宿主 `pacman-key --recv-keys` + `--lsign-key` alarm 构建密钥
     68B3537F...(幂等,已 lsign 则跳过);
  3. 生成 bootstrap pacman.conf(临时文件,`.tmp/` 或 mktemp):
     `Architecture = aarch64`、alarm 仓库段(core/extra/alarm/aur)
     `SigLevel = Required DatabaseOptional` + 选定 mirror;
     路径存全局 `PACSTRAP_CONF`。
- `distro_base_packages()`:echo `base linux-firmware btrfs-progs
  iptables-nft`(无 efifs;btrfs-progs 理由同 arch.sh 注释:
  mkinitcpio fsck hook 需要)。
- `distro_setup_repos()`(chroot 内、pacstrap 后):
  写入目标正式 pacman.conf(alarm 仓库段 + DatabaseOptional)、
  mirrorlist(`MY_ALARM_MIRROR`,见 §5.7)、
  `pacman-key --init` + `pacman-key --populate archlinuxarm`、
  然后 `pacman -Syu`。无 multilib(aarch64 无此概念)。
- `distro_kernel_packages()`:设 `KERNEL_PKG=linux-aarch64`、
  `KERNEL_PKGS="linux-aarch64 linux-aarch64-headers"`;并临时移除
  autodetect(§3.5):先 `cp mkinitcpio.conf mkinitcpio.conf.alarm-orig`
  备份,再 sed 从 HOOKS 删除 autodetect(备份恢复法,不做双向字符串
  拼接,避免脆弱的二次 sed)。
- `distro_post_install()`:
  1. **恢复 autodetect**:`mv mkinitcpio.conf.alarm-orig
     mkinitcpio.conf`。镜像内的 initramfs 已是安装期生成的完整版;
     此后真机上的内核更新在真实硬件上跑 mkinitcpio,autodetect 正常
     裁剪。中间无其他模块改 mkinitcpio.conf(全仓 grep 核实),整文件
     恢复安全。
  2. 复制 `$MNT_DIR/boot/dtbs/rockchip/rk3588-orangepi-5-plus.dtb` →
     `$MNT_DIR/efi/dtb/base/`(mkdir -p;文件缺失时 warn 不 die,
     固件内置 DTB 可兜底)。

**pacstrap 调用改造(modules/base.sh):** alarm 需要
`pacstrap -C "$PACSTRAP_CONF" -M` 且**不用 -K**(-K 在目标初始化空
keyring;alarm 走"拷贝宿主 keyring"默认路径,宿主已 lsign 构建密钥,
pacstrap 安装与目标内 pacman 立即可用;随后 distro_setup_repos 的
--populate 补齐 web-of-trust)。实现:distro 可设
`PACSTRAP_CONF`/`PACSTRAP_KEYRING_MODE` 全局变量,base.sh 按变量拼接
参数;x86 路径行为不变(-K 保留)。alarm.sh 在文件顶层(source 时)即设
`PACSTRAP_KEYRING_MODE=copy`;`PACSTRAP_CONF` 由 distro_host_preflight
生成后赋值。

### 5.3 主入口 arch-install

1. `--distro` 白名单加 `alarm`(现 :97 `arch|cachyos`)。
2. `DISTRO=alarm` 时强制 `CPUTYPE=generic`:跳过 detect_cputype
   (lib/common.sh 的 /sys 解析对 aarch64 无意义),且不装
   `"$CPUTYPE-ucode"`(lib/disk.sh:132 的 generic 逃逸口已存在,
   ucode 行也不写)。
3. `declare -F distro_host_preflight` 守卫调用(在 dry-run 门后、
   root 检查后,与 _cachyos_preflight_emulation 同位置)。
4. 末尾 qemu 验证提示:alarm 时改为 dd 指引
   (dd 到 SD/eMMC/NVMe;提醒目标介质不得残留 U-Boot)。

### 5.4 lib/disk.sh

1. 根分区 GUID 按架构:aarch64 用
   `B921B045-1DF0-41C3-AF44-4C6F280D3FAE`(Discoverable Partitions
   Spec "Linux root (ARM-64)"),x86_64 维持现值。systemd-repart 的
   `Type=root` 本身按架构解析,modules/growfs.sh 无需改(仅注释更新)。
2. XBOOTLDR 格式化:`DISTRO=alarm` 时 `mkfs.fat -F32`(原为 mkfs.ext4)。
   /efi 的 fmask=0077 惯例延续;/boot(FAT32)不加额外 fmask
   (random-seed 在 /efi,内核镜像无保密需求)。
3. `install_bootloader()`:alarm 分支写
   `linux /Image` + `initrd /initramfs-linux.img`,无 ucode 行;
   去掉 x86-only 的 `add_efi_memmap`(:154/:165,alarm 不需要);
   `options` 行其余部分(root=PARTUUID、mitigations=off、
   MY_KERNEL_PARAMS)不变。fallback 条目按 initramfs 存在性的
   现有逻辑自然生效(preset 无 fallback)。
4. efifs 驱动复制段(:117-120)对 alarm 自然跳过
   (`$MNT_DIR/boot/efi-drivers/` 不存在),加注释说明。

### 5.5 lib/common.sh

`detect_cputype` 不动;主入口在 `DISTRO=alarm` 时根本不调用它
(强制 generic)。函数注释补一行"aarch64 不走此路径"。

### 5.6 模块门禁(server profile 范围)

| 模块 | 改动 |
|---|---|
| modules/hardware.sh | `DISTRO=alarm` 时包列表剔除 `turbostat`(x86-only);linux-tools-meta 若 alarm 无此包一并剔除(实施时核实) |
| modules/dev-tools.sh | `DISTRO=alarm` 时跳过 `opencode`(alarm 404) |
| modules/pacman.sh | mirrorlist 四模式(copy/original/reflector/config)仅 arch/cachyos;alarm 的 mirror 由 distro_setup_repos 负责。archlinuxcn 段**保留不动**($arch 自动 aarch64;archlinuxcn-keyring/-mirrorlist-git 走 cn 仓库) |
| modules/cli-tools.sh | yay 保留(cn aarch64 提供;若实测缺失再单行门禁) |
| modules/mem-zram.sh | 无改动(架构无关);OPi5+ 用它替代 mem-zswap |
| modules/mem-zswap.sh | 无改动;OPi5+ 通过 SKIP_MODULES 排除(swapfile/zswap 逻辑本身架构无关,留作 aarch64 可用选项) |
| modules/zfs.sh / gpu-* / gpgpu / gaming / desktop-* | 不进 server profile,不动 |

### 5.7 配置项

- `config/config.example.sh` 新增:
  `MY_ALARM_MIRROR=""` —— 空则 geo 默认
  `https://mirror.archlinuxarm.org/$arch/$repo`;中国大陆建议
  `https://mirrors.ustc.edu.cn/archlinuxarm/$arch/$repo`。
- `devices/example.sh` 模板增加 alarm 注释段(DISTRO=alarm 用法)。
- 新设备 `devices/opi5plus.sh`(gitignored,不入库):
  `DISTRO=alarm`、`MY_HOSTNAME=opi5plus`、
  `SKIP_MODULES=mem-zswap`、`EXTRA_MODULES=mem-zram`、
  `MY_KERNEL_PARAMS="console=ttyS2,1500000"`、
  `MY_ALARM_MIRROR=USTC`、`SIZE=8G`(无 swapfile,server 装机约 3-4G,
  真机首启 repart+growfs 扩满)。

### 5.8 profiles

`profiles/server.conf` 不动。文档(README)注明:**alarm 当前仅验证
server profile**;desktop profile 在 aarch64 未验证,强行使用自负。

## 6. 错误处理

- binfmt 未注册 / 无 F flag → die,提示宿主安装
  qemu-user-static{,-binfmt}(distro_host_preflight)。
- alarm 构建密钥 recv/lsign 失败 → die(网络/keyserver 问题)。
- pacstrap / pacman 在 alarm 仓库包缺失 → pacman_install 既有
  重试×3 后 die;门禁清单内包名实施时逐一对照 §3.7 核实。
- 内核 dtb 缺失(rk3588-orangepi-5-plus.dtb)→ warn 不 die
  (固件内置 DTB 兜底)。
- qemu-user 下 pacman-key --init 熵不足/慢 → 属预期,文档注明等待。

## 7. 测试与验证

1. `tests/run.sh` 新增断言:
   - --distro 白名单含 alarm;
   - alarm GUID B921B045 出现在 lib/disk.sh;
   - install_bootloader 的 alarm 分支:`linux /Image`、
     `initramfs-linux.img`、无 amd-ucode、alarm 分支无 add_efi_memmap;
   - mkinitcpio.conf 的 autodetect 临时移除 + 末尾恢复逻辑存在
     (备份文件法);
   - hardware.sh turbostat 有 alarm 门禁;dev-tools.sh opencode 有
     alarm 门禁;pacman.sh mirrorlist 段有 alarm 跳过、archlinuxcn 段
     无门禁;
   - distro/alarm.sh 四函数 + distro_host_preflight 存在;
   - devices/example.sh 含 alarm 示例。
   现有 x86 断言全部不动(回归)。
2. `shellcheck` 对全部改动文件零新增告警。
3. **真机验证(验收标准)**:x86_64 宿主构建镜像 → dd 到 NVMe/SD →
   OPi5+ 启动:
   - systemd-boot 出现 Arch Linux ARM (alarm) 条目并正常进系统;
   - `systemctl --failed` 为空;
   - repart 扩分区 + systemd-growfs-root 扩 btrfs 到盘满
     (journalctl 有 Partition table written + resize);
   - SSH 通(sshdgenkeys 首启生成 host key);
   - zram0 存在且 zstd(zcat /sys/block/zram0/comp_algorithm);
   - zswap 已关(/sys/module/zswap/parameters/enabled = N);
   - 双网卡 eth 均可见(RTL8125 固件来自 linux-firmware);
   - `uname -m` = aarch64,`uname -r` 为 linux-aarch64 版本;
   - 串口 console(ttyS2,1500000)有输出。

## 8. 风险与缓解

| 风险 | 缓解 |
|---|---|
| autodetect 裁剪导致 eMMC/SD 起不来 | 安装期临时删 autodetect、末尾恢复(§3.5/§5.2),真机三种介质验证 |
| 固件 DTB 与内核不配套 | /efi/dtb/base/ override 通道已内建;固件 fix-up 优先 |
| binfmt 慢导致构建耗时翻倍 | 预期内;文档注明;qemu-user 下避免重活(gpg 已在宿主做完大半) |
| alarm 数据库不签名被误以为损坏 | pacman.conf DatabaseOptional + README 说明是上游设计 |
| 宿主 keyring 持久改动 | distro_host_preflight 幂等;README 写明 |
| archlinuxcn aarch64 个别包缺失 | 构建实测;缺则单行门禁并记录 |
| SPI 曾刷 U-Boot 的机器冲突 | README 须知:SPI/SD/eMMC 不得残留 U-Boot |

## 9. 后续(不在本次范围)

desktop profile on aarch64 验证;efifs 移植评估;gpu-mali(Panfrost)
模块;zfs-dkms on aarch64; qemu aarch64 模拟验证管线。

## 10. 文档同步清单(实施时一并完成)

- README.md / README.zh-CN.md:--distro alarm 用法、宿主依赖
  (qemu-user-static{,-binfmt})、宿主 keyring 改动说明、OPi5+ dd
  须知(无 U-Boot 残留)、alarm 仅 server profile。
- AGENTS.md:目录结构加 distro/alarm.sh;CHANGELOG 条目。
- config/config.example.sh、devices/example.sh:见 §5.7。
