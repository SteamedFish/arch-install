# arch-install

个人 Arch / CachyOS 安装器。纯 bash,模块化。自用项目,代码组织与文档以供参考。

从单文件脚本重构而来:同一功能的装包、配置、服务启用收拢在同一个模块文件内;所有个人信息(用户名、密钥、内网地址、备份目标)移到 gitignored 的 `config/`,仓库可安全公开。

## 特性

- **双发行版**:Arch 与 CachyOS(内核变体与 v3/v4/znver4 仓库优化可选;keyring/mirrorlist 版本实时从 CDN 查询,也可用 `MY_CACHYOS_MIRRORLIST` 自带镜像列表)
- **异构构建**:`--cputype amd|intel` 指定目标机 CPU(如在 Intel 机器上给 AMD 机器装)
- **双目标**:raw 磁盘镜像(自动 losetup)或物理盘(自动识别,整盘抹掉,交互确认 + `--force` + 占用预检)
- **模块化**:每功能一个 `modules/*.sh`,声明 requires/conflicts/before,解析器自动闭包 + 拓扑排序
- **预设**:`server` / `desktop`(niri 或 KDE);VPS = server + `--skip-modules hardware`;`--extra-modules` / `--skip-modules` 任意增减
- **设备预设**:`--device NAME` 加载 `devices/NAME.sh`(gitignored,`devices/example.sh` 为 tracked 模板),固化单台设备的 CLI 默认值(`--distro`、`--cputype`、内核变体、`--extra-modules` 等)与 `MY_*` 覆盖。叠加顺序:内置默认 → `config.sh` → 设备文件 → CLI 显式参数。`TARGET`/`--force`/`--dry-run` 不可固化;`--profile` 约定每次显式传
- **mirrorlist 四来源**:copy 宿主机 / 官方默认 / reflector 生成 / config 文件。文件名始终与官方包一致(`mirrorlist`、`archcn-mirrorlist`、`cachyos-mirrorlist`),随时可切回包管理;`original` 模式直接安装官方包
- **首启自动扩容**:systemd-repart,GPT 分区与 btrfs 文件系统都扩到最大
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

## 目录

```
arch-install          主入口:参数解析、流程编排、cleanup trap
lib/                  common(日志/依赖检查) disk(分区/挂载/bootctl) chroot(封装) modules(解析器)
distro/               arch.sh / cachyos.sh(发行版差异:仓库、keyring、内核)
modules/              功能模块(接口见下)
profiles/             server.conf / desktop.conf(MODULES 预设)
config/               config.example.sh + hooks.example.sh(tracked 模板);
                      config.sh + hooks.sh(gitignored,你的个人配置)
devices/              example.sh(tracked 模板);NAME.sh 设备预设
                      (gitignored,`--device NAME` 加载)
tests/run.sh          纯 bash 自测(语法、模块契约、硬约定、解析器单测、dry-run)
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

`[archlinuxcn]` 源由 pacman 模块保证必装——`rime-ice-git`、`an-anime-game-launcher-bwrap` 等包只存在于该源。KDE 专属应用(dolphin、kate、tokodon 等)在 desktop-kde 模块;gui-apps 只放 DE 无关的应用。`[multilib]` 由 `distro_setup_repos` 无条件启用(Arch 与 CachyOS 均在 distro_setup_repos 内 uncomment),即使 `--skip-modules pacman` 也能保留 wine/steam 等 32 位依赖。

## 模块接口

```bash
mod_requires()  { echo audio fonts; }        # 依赖,自动补全并排在前面
mod_conflicts() { echo desktop-kde; }        # 冲突,同装报错
mod_before()    { echo desktop-niri; }       # 顺序约束(装包顺序敏感时用,必注释原因)
mod_install()   { pacman_install xxx; chroot_write_file ...; chroot_enable ...; }
```

约定:

- 模块内**禁止硬编码个人信息**;只读 `MY_*` 变量,为空则跳过(`tests/run.sh` 强制检查)
- 同一功能的装包/配置/enable 必须在同一文件内
- `pacman_install` 每次装完自动 `pacman -Sc`(镜像空间保护)
- 装包顺序敏感处必须注释(pacman 对 `a or b` 依赖按字母序选 a 的坑)

新增功能:写 `modules/foo.sh` → 加进 profile 或用 `--extra-modules` → 同步 AGENTS.md / README / CHANGELOG。

## 文档

- 设计:`docs/plans/2026-07-28-arch-install-design.md`
- 计划:`docs/plans/2026-07-28-arch-install-plan.md`
- 约定与 TODO:`AGENTS.md`

[English README](README.md)
