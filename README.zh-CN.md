# arch-install

个人 Arch / CachyOS / Arch Linux ARM(aarch64)安装器。纯 bash,模块化。自用项目,代码组织与文档以供参考。

从单文件脚本重构而来:同一功能的装包、配置、服务启用收拢在同一个模块文件内;所有个人信息(用户名、密钥、内网地址、备份目标)移到 gitignored 的 `config/`,仓库可安全公开。

## 特性

- **三发行版**:Arch、CachyOS(内核变体与 v3/v4/znver4 仓库优化可选;keyring/mirrorlist 版本实时从 CDN 查询,也可用 `MY_CACHYOS_MIRRORLIST` 自带镜像列表)、Arch Linux ARM(`--distro alarm`,从 x86_64 宿主交叉构建 aarch64 镜像,见下方专节)
- **异构构建**:`--cputype amd|intel` 指定目标机 CPU(如在 Intel 机器上给 AMD 机器装)
- **双目标**:raw 磁盘镜像(自动 losetup)或物理盘(自动识别,整盘抹掉,交互确认 + `--force` + 占用预检)
- **模块化**:每功能一个 `modules/*.sh`,声明 requires/conflicts/before,解析器自动闭包 + 拓扑排序
- **预设**:`server` / `desktop`(niri 或 KDE);VPS = server + `--skip-modules hardware`;`--extra-modules` / `--skip-modules` 任意增减
- **设备预设**:`--device NAME` 加载 `devices/NAME.sh`(gitignored,`devices/example.sh` 为 tracked 模板),固化单台设备的 CLI 默认值(`--distro`、`--cputype`、内核变体、`--extra-modules` 等)与 `MY_*` 覆盖。叠加顺序:内置默认 → `config.sh` → 设备文件 → CLI 显式参数。`TARGET`/`--force`/`--dry-run` 不可固化;`--profile` 约定每次显式传
- **mirrorlist 四来源**:copy 宿主机 / 官方默认 / reflector 生成 / config 文件。文件名始终与官方包一致(`mirrorlist`、`archcn-mirrorlist`、`cachyos-mirrorlist`),随时可切回包管理;`original` 模式直接安装官方包
- **首启自动扩容**:systemd-repart,GPT 分区与 btrfs 文件系统都扩到最大
- **btrfs 热写目录 NOCOW**:根文件系统为 btrfs 时,安装期对 `/var/log/journal` 执行 `chattr +C`;auditd 模块同款处理 `/var/log/audit`,virt 模块同款处理 `/var/lib/libvirt/images`——高频追加的日志与随机写的 VM 镜像跳过 COW,避免碎片化
- **内存选项**:默认 `mem-zswap`(tmpfiles.d 纯配置文件 + btrfs NOCOW swapfile 后备,`MY_SWAP_SIZE` 默认 4G;`0` 退回 zram);可选 `mem-zram`(zram-generator);不想要任何 swap 就删掉该模块——两者互斥
- **稀疏镜像**:raw 镜像为稀疏文件(宿主机实际占用 = 真实数据量),清理时 fstrim 把释放的块 punch 回文件
- **secrets 策略**:copy(镜像)/ firstboot(物理盘)/ keyfile(git-crypt 对称密钥)/ none
- **隐私安全**:个人信息全在 `config/config.sh` 与 `config/hooks.sh`(gitignored),模板 tracked

## 用法

```bash
cp config/config.example.sh config/config.sh   # 填 MY_USERNAME 等
sudo ./arch-install --target system.img --size 15G --profile desktop --desktop niri
sudo ./arch-install --target /dev/sda --profile server --force
sudo ./arch-install --target vps.img --profile server --skip-modules hardware
sudo ./arch-install --target cachy.img --distro cachyos --cachyos-kernel bore
sudo ./arch-install --device hx370 --target /dev/nvme0n1 --profile desktop   # 设备预设:参数固化在 devices/hx370.sh
./arch-install --target x.img --profile desktop --dry-run   # 预览,不需 root
./arch-install --modules   # 列出全部模块、依赖与顺序约束
```

完整参数:`./arch-install --help`。

镜像验证:

```bash
qemu-system-x86_64 -m 4G -bios /usr/share/ovmf/x64/OVMF.4m.fd -drive file=system.img,format=raw
```

aarch64(`--distro alarm`)镜像不能用 qemu-system-x86_64 验证:需真机或 qemu-system-aarch64(本安装器未提供该仿真路径)。

## Arch Linux ARM(aarch64)

`--distro alarm` 从 x86_64 宿主交叉构建 Arch Linux ARM 镜像。目标:RK3588 开发板(Orange Pi 5 Plus,SPI 已刷 edk2-rk3588 UEFI 固件);镜像构建与真机启动验证为后续任务。

宿主要求:

- `qemu-user-static` + `qemu-user-static-binfmt`,`qemu-aarch64` binfmt 规则必须**带 F(fix_binary)flag** 注册,否则 chroot 内无法执行 aarch64 二进制。宿主 preflight 在动磁盘前检查:规则缺失、未 enabled、缺 F 都会直接报错退出。
- alarm 构建密钥(`68B3537F39A313B3E574D06777193F152BDBE6A6`)在 pacstrap 前 recv + lsign 进**宿主** pacman keyring。这是对宿主的持久修改,一次即可。
- 构建耗时约翻倍:chroot 内每个二进制都经 qemu-user 执行,gpg 操作(`pacman-key --init`)尤其慢,属预期。

`MY_ALARM_MIRROR` 指定镜像,值需含 `$arch`/`$repo` 占位符(如 `https://mirrors.ustc.edu.cn/archlinuxarm/$arch/$repo`);留空用 GeoDNS 默认 `mirror.archlinuxarm.org`。

OPi5+ 设备预设示例(`devices/opi5plus.sh` gitignored,模板见 `devices/example.sh`):

```bash
sudo ./arch-install --device opi5plus --target opi5plus.img --profile server
dd if=opi5plus.img of=/dev/sdX bs=4M status=progress conv=fsync   # 写入 SD / eMMC / NVMe
# 首启:systemd-repart + systemd-growfs 把根分区与 btrfs 扩到整盘
```

> **注意**:启动介质(SD / eMMC / NVMe)上不得残留 U-Boot,否则 edk2-rk3588 固件可能优先走残留的 U-Boot、引导链出错。SPI 例外:SPI 上必须是 edk2-rk3588。

当前限制:

- alarm 仅验证过 `server` profile;`desktop` profile 未实测。
- alarm 无 `efifs` 包,XBOOTLDR(`/boot`)用 FAT32 而非 ext4。
- 引导条目不加 `add_efi_memmap`(x86-only 选项)。
- 内核为 `linux-aarch64`;mkinitcpio 的 `autodetect` 安装期临时移除(qemu-user 下读到的是宿主 x86_64 的 /sys),post_install 恢复。

## 目录

```
arch-install          主入口:参数解析、流程编排、cleanup trap
lib/                  common(日志/依赖检查) disk(分区/挂载/bootctl) chroot(封装) modules(解析器)
distro/               arch.sh / cachyos.sh / alarm.sh(发行版差异:仓库、keyring、内核)
modules/              功能模块(接口见下)
profiles/             server.conf / desktop.conf(MODULES 预设)
config/               config.example.sh + hooks.example.sh(tracked 模板);
                      config.sh + hooks.sh(gitignored,你的个人配置)
devices/              example.sh(tracked 模板);NAME.sh 设备预设
                      (gitignored,`--device NAME` 加载)
tests/                bats 测试(test_helper.bash + 9 个 *.bats;syntax/module_contract/
                      profile_contract/hard_constraints/resolver/dryrun/feature_specifics/
                      devices/firewall);运行:bats tests/(需 bats 包,已装在 [extra])
docs/plans/           设计文档与执行计划
```

## 模块速览

```
基础:      base pacman growfs ssh
系统:      security filesystems chrony sysctl firewall debug monitoring hardware backup
网络:      network-networkd(server)/ network-nm(desktop)
工具:      cli-tools dev-tools docker virt
桌面:      audio fonts ime bluetooth desktop-niri desktop-kde gui-apps gaming
显卡(可选): gpu-amd gpu-nvidia gpu-intel gpgpu(OpenCL/ROCm/CUDA,`MY_GPGPU` 选 vendor)
存储(可选): zfs(OpenZFS 数据池,`--extra-modules zfs`;根文件系统仍为 btrfs)
```

`[archlinuxcn]` 源由 pacman 模块保证必装——`rime-ice-git`、`an-anime-game-launcher-bwrap` 等包只存在于该源。KDE 专属应用(dolphin、kate、tokodon 等)在 desktop-kde 模块;gui-apps 只放 DE 无关的应用。`[multilib]` 由 `distro_setup_repos` 无条件启用(Arch 与 CachyOS 均在 distro_setup_repos 内 uncomment),即使 `--skip-modules pacman` 也能保留 wine/steam 等 32 位依赖。`--distro alarm`(aarch64)下:hardware 不装 turbostat(x86-only)、dev-tools 不装 opencode/shellcheck/biome、cli-tools 不装 hwinfo/vi(alarm 各仓库与 archlinuxcn aarch64 均无,已对包数据库本地比对确认)、yay 来自 archlinuxcn 的 aarch64 仓。

## 模块接口

```bash
mod_requires()  { echo audio fonts; }        # 依赖,自动补全并排在前面
mod_conflicts() { echo desktop-kde; }        # 冲突,同装报错
mod_before()    { echo desktop-niri; }       # 顺序约束(装包顺序敏感时用,必注释原因)
mod_install()   { pacman_install xxx; chroot_write_file ...; chroot_enable ...; }
```

约定:

- 模块内**禁止硬编码个人信息**;只读 `MY_*` 变量,为空则跳过(`tests/hard_constraints.bats` 强制检查)
- 同一功能的装包/配置/enable 必须在同一文件内
- `pacman_install` 每次装完自动 `pacman -Sc`(镜像空间保护)
- 装包顺序敏感处必须注释(pacman 对 `a or b` 依赖按字母序选 a 的坑)

新增功能:写 `modules/foo.sh` → 加进 profile 或用 `--extra-modules` → 同步 AGENTS.md / README / CHANGELOG。

## 文档

- 设计:`docs/plans/2026-07-28-arch-install-design.md`
- 计划:`docs/plans/2026-07-28-arch-install-plan.md`
- 约定与 TODO:`AGENTS.md`

[English README](README.md)
