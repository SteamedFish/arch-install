# arch-install 设计文档

> 日期:2026-07-28
> 状态:已确认(头脑风暴完成)
> 前身:`~/work/arch-image-creation/create-os-image.sh`(844 行单文件 bash)

## 1. 目标与需求

把个人 Arch Linux 安装脚本重写为一个模块化项目:

1. 支持 Arch 与 CachyOS,CachyOS 的内核变体与仓库优化等级(v3/v4/znver4)用参数选择
2. 所有个人内容(用户名、密钥、备份目标等)收进 gitignored config,仓库可安全公开
3. 纯自用项目,但代码组织与文档要清晰,方便他人参考修改
4. 高内聚:同一功能的包装、配置写、服务 enable 放在同一个模块文件里
5. 假设宿主机是 Arch;运行前检查依赖,缺失则提示安装命令并退出
6. mirrorlist 四种来源可选:copy(拷当前系统)/ original(软件包自带默认)/ reflector(生成)/ config(从配置文件读)
7. 安装目标自动识别:块设备 → 物理盘(整盘抹掉);文件路径 → raw 磁盘镜像
8. 首次启动自动把根分区扩到磁盘上限(systemd-repart)

## 2. 总体架构

模块化 bash(不引入其他语言/框架)。仓库布局:

```
arch-install/
├── arch-install              # 主入口(参数解析、流程编排、cleanup trap)
├── lib/
│   ├── common.sh             # 日志、die、依赖检查、变量工具
│   ├── disk.sh               # 目标识别、占用检查、分区、格式化、挂载、losetup 封装
│   ├── chroot.sh             # arch-chroot 封装、chroot 内装包/写文件/enable 服务
│   └── modules.sh            # 模块加载、依赖闭包解析、conflicts 检查
├── distro/
│   ├── arch.sh               # distro_* 接口的 Arch 实现
│   └── cachyos.sh            # CachyOS 实现(keyring、v3/v4/znver4、内核变体)
├── modules/                  # 每功能一文件,见第 3 节
├── profiles/
│   ├── server.conf           # MODULES=(...)
│   └── desktop.conf
├── config/
│   ├── config.example.sh     # tracked 模板,含全部 MY_* 变量与注释
│   ├── config.sh             # gitignored,用户实际配置
│   └── hooks.sh              # gitignored(或从 example 复制),私活逻辑
├── docs/plans/               # 设计文档与实现计划
├── README.md / README.zh-CN.md
└── AGENTS.md                 # 项目说明、目录约定、TODO/CHANGELOG
```

`.gitignore`:`config/config.sh`、`config/hooks.sh`、`/tmp/`、`*.img`。

## 3. 模块系统

### 3.1 模块接口

每个模块是 `modules/<name>.sh`,被 source 后可定义:

```bash
mod_requires()  # 可选:echo 依赖的模块名(空格分隔),主脚本递归补全闭包
mod_conflicts() # 可选:echo 互斥的模块名(如 desktop-kde ↔ desktop-niri)
mod_install()   # 唯一必实现入口:装包 + 写配置 + enable 服务,全部经 lib/chroot.sh
```

模块内零硬编码个人信息:只读 `MY_*` config 变量;关键变量为空则整个模块跳过
(如 `backup.sh` 检查 `MY_BACKUP_TARGET`)并打印 skip 日志。

包安装收在模块内部(需求 4 的极致内聚)。代价:pacman 小事务次数变多
(约 20 次 vs 原来 1 次,慢几分钟),自用场景可接受。

### 3.2 模块清单

| 模块 | 内容 | 归属 |
|---|---|---|
| `base` | pacstrap、内核、fstab、bootctl、locale、时区、hostname | 全部(distro 驱动) |
| `pacman` | pacman.conf 调优(archlinuxcn 可选)、mirrorlist 四来源 | 全部 |
| `growfs` | `/etc/repart.d/50-root.conf`(systemd-repart,需求 8) | 全部 |
| `ssh` | openssh + `sshd_config.d/99-my.conf`(端口 `$MY_SSH_PORT`)+ enable | 全部 |
| `cli-tools` | eza/zsh/tmux/bat/ripgrep/fd/skim/atuin/zoxide/yazi/htop/strace/tcpdump/rsync/curl/aria2/7zip 等 | 全部 |
| `dev-tools` | base-devel/git/neovim/cmake/shfmt/prettier/entr 等 | 全部 |
| `security` | pass/git-crypt/gnupg 相关 | 全部 |
| `filesystems` | btrfs-progs/xfsprogs/ntfs-3g/exfatprogs/dosfstools/sshfs/nfs-utils | 全部 |
| `chrony` | chrony + NTP 服务器(`$MY_NTP_SERVERS`)+ enable | 全部 |
| `sysctl` | `/etc/sysctl.d/$MY_USERNAME.conf`(BBR/fq_codel/buffer 等) | 全部 |
| `firewall` | iptables-nft + 规则(放行 `$MY_SSH_PORT`)+ enable | 全部(含 desktop,个人习惯) |
| `network-networkd` | systemd-networkd + `00-ether.link`/`00-dhcp.network` | server(与 network-nm 互斥) |
| `network-nm` | NetworkManager + enable | desktop(与 network-networkd 互斥) |
| `hardware` | smartmontools/lm_sensors/irqbalance/cpupower/nvme-cli/linux-tools | server 默认,vps 用法时 skip |
| `monitoring` | prometheus node/smartctl/systemd exporters + conf.d | server 可选 |
| `docker` | docker/docker-compose/nerdctl/buildx/rootless/podman/passt/fuse-overlayfs/pigz + subuid | 可选(--extra-modules) |
| `virt` | qemu-img/cloud-guest-utils | server |
| `backup` | 备份脚本 + systemd timer;`$MY_BACKUP_TARGET` 空则跳过 | 可选(config 驱动) |
| `audio` | pipewire/pipewire-alsa/pipewire-pulse/wireplumber | desktop 必需(被 desktop-* require) |
| `fonts` | noto/noto-cjk/noto-emoji + ttf-nerd-fonts-symbols | desktop 必需 |
| `ime` | fcitx5/fcitx5-rime/fcitx5-configtool + rime-ice(可选) | desktop 必需 |
| `bluetooth` | bluez + enable | desktop |
| `desktop-kde` | plasma/sddm(autologin 同样由 `MY_GREETER_AUTOLOGIN` 控制;与 desktop-niri 互斥) | 二选一 |
| `desktop-niri` | 见第 9 节 | 二选一 |
| `gaming` | wine/winetricks/proton-ge/lutris/gamescope/mangohud | desktop 可选 |

### 3.3 Profile

`profiles/*.conf` 只定义 `MODULES=(...)` 数组(必需模块)。

- `server.conf`:base pacman growfs ssh cli-tools dev-tools security filesystems
  chrony sysctl firewall network-networkd hardware monitoring virt backup
- `desktop.conf`:server 全部 − network-networkd − monitoring
  + network-nm audio fonts ime bluetooth gaming + desktop-niri(或 desktop-kde)
- 不设独立 vps profile:VPS = `--profile server --skip-modules hardware`
  (README 中说明)

增减:`--extra-modules a,b` / `--skip-modules c,d`;`mod_requires` 闭包自动补;
`mod_conflicts` 命中则报错退出。

## 4. CLI

```
arch-install --target /dev/sda --profile desktop --desktop niri
arch-install --target /data/vm.img --size 20G --profile server --skip-modules hardware
arch-install --target /dev/nvme0n1 --distro cachyos --cachyos-kernel bore --force
```

| 参数 | 说明 | 默认 |
|---|---|---|
| `--target PATH` | 必需;块设备 → 物理盘,文件 → 镜像 | — |
| `--size SIZE` | 镜像模式大小 | 20G |
| `--profile` | server / desktop | server |
| `--distro` | arch / cachyos | arch |
| `--desktop` | niri / kde(仅 desktop profile) | niri |
| `--cachyos-kernel` | default/bore/bmq/lts/server/hardened/rt-bore/eevdf/rc | default |
| `--mirrorlist` | copy / original / reflector / config | copy |
| `--extra-modules` / `--skip-modules` | 逗号分隔 | — |
| `--dry-run` | 打印计划(目标、分区、模块闭包、包清单)后退出 | off |
| `--force` | 跳过物理盘确认 | off |

## 5. distro 抽象

`distro/arch.sh` 与 `distro/cachyos.sh` 实现同一接口:

```
distro_base_packages()    # pacstrap 包集
distro_setup_repos()      # 仓库/密钥配置(chroot 前)
distro_kernel_packages()  # 内核包名
distro_post_install()     # 发行版特有收尾(chroot 内)
```

**CachyOS 两阶段引导**(依据官方 cachyos-repo-add-script 与 wiki):

1. 正常 `pacstrap base linux-firmware`
2. chroot 内从 URL 装 `cachyos-keyring`、`cachyos-mirrorlist`、
   `cachyos-v3-mirrorlist`、`cachyos-v4-mirrorlist`
3. 在 `[core]` **之前**插入 `[cachyos-v3|v4|znver4]`、
   `[cachyos-core-*]`、`[cachyos-extra-*]`、`[cachyos]` section,
   `Architecture = auto`
4. `pacman -Syu`,然后装 `linux-cachyos*`(替换 stock linux)+ `cachyos-settings`
5. CPU 检测:`/lib/ld-linux-x86-64.so.2 --help | grep supported` 判 v3/v4;
   `gcc -march=native` 判 znver4(znver4 > v4 > v3 优先级);可用
   `--cachyos-repo v3|v4|znver4|auto` 覆盖,默认 auto

mirrorlist 四来源逻辑对 CachyOS 的 mirrorlist 同样生效
(reflector 来源对应 `cachyos-rate-mirrors`,需网络,不可用时回退包默认并警告)。

## 6. 磁盘、镜像与扩容

- **识别**:`-b $target` → 物理盘;否则镜像(qemu-img -f raw 创建 + `losetup -P` 挂 loop)
- **物理盘安全**:整盘抹掉;装前 `lsof`/`fuser`/mount 占用检查;交互确认
  (显示 lsblk),`--force` 跳过
- **分区**(与现脚本一致,GPT):
  p1 EFI System 256MiB fat32 → `/efi`;
  p2 Linux extended boot (XBOOTLDR) 1GiB ext4 → `/boot`;
  p3 Linux root (x86-64) 剩余 btrfs,subvol `ArchLinux`,
  fstab `rootflags=subvol=/ArchLinux`
- **引导**:`bootctl --esp-path=/efi --boot-path=/boot --no-variables install`,
  entries 含 `mitigations=off`、CPU 微码(`$CPUTYPE-ucode`,从 `/proc/cpuinfo` 判)
- **扩容**(需求 8):安装时写 `/etc/repart.d/50-root.conf`
  (`Type=linux-root` + `GrowFileSystem=yes`);systemd-repart 首启自动
  扩分区 + btrfs 在线扩容,幂等;分区类型已符合 DPS 规范,无需额外处理
- **cleanup trap**:任何失败 umount + losetup -d,不留半挂载状态

## 7. mirrorlist 四来源(需求 6)

`--mirrorlist copy|original|reflector|config`:

| 来源 | 行为 |
|---|---|
| `copy` | 拷当前系统 `/etc/pacman.d/mirrorlist` |
| `original` | 不动,用 pacman 包自带默认 |
| `reflector` | chroot 内 `reflector --country China --age 12 --sort rate --save ...`(需网络;CachyOS 用 `cachyos-rate-mirrors`) |
| `config` | 从 `$MY_MIRRORLIST_FILE` 指定路径拷入 |

reflector 失败(无网络)时回退 original 并警告。

## 8. 个人配置与密钥(需求 2、鸡生蛋问题)

`config/config.example.sh` 定义全部 `MY_*` 变量(运行前检查:
`config.sh` 不存在则提示复制模板并退出)。关键变量:

```
MY_USERNAME MY_HOSTNAME MY_TIMEZONE MY_SSH_PORT MY_NTP_SERVERS
MY_BACKUP_TARGET MY_GITCRYPT_KEYFILE MY_SECRETS_MODE MY_GREETER_AUTOLOGIN
MY_MIRRORLIST_FILE MY_EXTRA_PACKAGES ...
```

`config/hooks.sh` 定义可选钩子:`hook_post_install`(拷 .ssh/.gnupg、
yadm clone + git-crypt unlock、LazyVim/zinit 等)。

**密钥注入三档**(`MY_SECRETS_MODE`,默认按目标类型:auto → 镜像 copy / 物理 firstboot):

| 模式 | 行为 |
|---|---|
| `copy` | hook 把当前系统 `~/.ssh`、`~/.gnupg` rsync 进目标用户家目录;装完即可 yadm clone + unlock |
| `firstboot` | 镜像零私钥;放 `~/.local/bin/first-boot-setup` 引导脚本(从别机 scp 密钥后自动 yadm clone + git-crypt unlock + bootstrap) |
| `keyfile` | 用 `git-crypt export-key` 的对称密钥 + https 匿名 clone(仓库公开),不碰 SSH/GPG 私钥即可解开 dotfiles |
| `none` | 完全跳过 |

## 9. desktop-niri 模块

**包**(全部官方 extra 源,零 AUR):

```
niri uwsm libnewt xwayland-satellite
xdg-desktop-portal-gnome xdg-desktop-portal-gtk gnome-keyring
dbus-broker
greetd greetd-tuigreet
polkit polkit-kde-agent
dms-shell dms-shell-niri quickshell matugen cava qt6-multimedia-ffmpeg
kitty alacritty fuzzel mako waybar swaybg swaylock swayidle
awww udiskie brightnessctl
```

**系统级配置**:

- `systemctl --global enable dbus-broker.service`(uwsm 推荐)
- `/etc/greetd/config.toml`:
  ```toml
  [terminal]
  vt = 1
  [default_session]
  command = "tuigreet --time --remember --cmd 'uwsm start niri.desktop'"
  user = "greeter"
  ```
- autologin 开关(`MY_GREETER_AUTOLOGIN=yes`,台式机用;笔记本必须 no):
  追加 `[initial_session] command = "uwsm start niri.desktop" user = "$MY_USERNAME"`
- enable `greetd.service`

**用户态不碰**(归 dotfiles/yadm):dms.service enable、polkit agent 启动、
fcitx5 自启、`~/.config/uwsm/env`、niri config.kdl。模块注释中说明边界。

mod_requires:audio fonts ime network-nm bluetooth。
mod_conflicts:desktop-kde。

## 10. 执行流程

```
1. check_deps         # 需求5:列缺失依赖 + 安装命令,退出
2. parse_args + load_config
3. detect_target      # 物理盘:占用检查 + 确认;镜像:qemu-img + losetup
4. resolve_modules    # profile ± extra/skip + requires 闭包 + conflicts
5. partition/format/mount
6. pacstrap(distro_base_packages)
7. distro_setup_repos # 含 mirrorlist 四来源
8. 内核 + fstab + bootctl + locale/时区/hostname
9. growfs drop-in
10. for m in resolved_modules: mod_install
11. hook_post_install # secrets 三档逻辑
12. cleanup           # machine-id、random-seed、umount、losetup -d
13. 完成摘要           # 镜像模式附 qemu 启动示例
```

`--dry-run` 在第 5 步前输出完整计划并退出。

## 11. 错误处理

- 全程 `set -euo pipefail`;cleanup trap 兜底
- 模块失败:报清模块名与阶段,不静默继续
- 依赖检查:需求 5,启动即做
- 可重入性不保证(从头再来成本低于维护幂等)

## 12. 测试策略

- `bash -n` + shellcheck CI 级检查(本地手动,不配 CI)
- `--dry-run` 验证参数/模块解析
- 端到端:镜像模式 + qemu 启动验证(sshd 起来、根分区已扩容、greetd 正常)
  —— 手动执行,写进 README 的验证清单

## 13. 文档计划

- `README.md`(English)+ `README.zh-CN.md`:用法、参数、模块表、profile、
  config 说明、vps 用法、验证清单
- `AGENTS.md`:目录约定、模块接口规范、TODO/CHANGELOG
- 每模块文件头部注释:功能、依赖变量、enable 的服务
- niri/uwsm 个人配置建议:已单独存于 `arch-image-creation/niri-uwsm-notes.md`(不进本仓库)
