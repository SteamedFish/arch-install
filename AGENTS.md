# AGENTS.md — arch-install

个人 Arch/CachyOS 安装器。模块化 bash。设计:`docs/plans/2026-07-28-arch-install-design.md`,
执行计划:`docs/plans/2026-07-28-arch-install-plan.md`。

## 目录结构

```
arch-install          主入口:参数解析、流程编排、cleanup trap
lib/common.sh         日志(log/info/warn/die)、check_deps、工具函数
lib/disk.sh           目标识别(物理盘/镜像)、占用检查、分区、格式化、挂载、losetup
lib/chroot.sh         arch-chroot 封装:chroot_run、pacman_install(含 pacman -Sc)、
                      chroot_write_file、chroot_enable
lib/modules.sh        模块加载、requires 闭包、conflicts 校验、拓扑排序(mod_before)
distro/arch.sh        distro_base_packages/setup_repos/kernel_packages/post_install
distro/cachyos.sh     CachyOS 实现:keyring、v3/v4/znver4 检测、内核变体
modules/*.sh          功能模块,接口见 plan 文档
profiles/*.conf       MODULES=(...) 预设(server.conf desktop.conf)
config/config.example.sh  tracked 模板(全部 MY_* 变量)
config/config.sh      gitignored 用户配置
config/hooks.example.sh   tracked 钩子模板
config/hooks.sh       gitignored 私活逻辑
devices/example.sh    tracked 设备模板;devices/*.sh gitignored(--device NAME
                      固化设备级 CLI 默认值与 MY_* 变量,
                      叠加:内置默认→config.sh→设备文件→CLI)
tests/run.sh          纯 bash 测试(无外部依赖)
docs/plans/           设计与计划文档
```

## 硬约定

- 模块内禁止硬编码个人信息;只读 `MY_*`,为空则 skip
- 同一功能的装包/配置/enable 必须在同一模块文件内
- 安装顺序敏感处必须注释原因(pacman 字母序坑)
- `pacman_install` 后自动 `pacman -Sc`(镜像空间保护)
- 新功能同步更新:本文件、README、CHANGELOG

## TODO

- [x] 核心骨架(lib + 主入口)
- [x] distro/arch + distro/cachyos
- [x] 全部模块(24 个)
- [x] profiles + config 模板
- [x] README × 2
- [x] 镜像端到端 qemu 验证(OVMF+NVMe 仿真,SSH 全链路实测通过)
- [x] 默认启用 auditd.service(2026-07-31)
- [ ] anything-sync-daemon(原脚本 TODO,待定)

## CHANGELOG

- 2026-08-22:移除 `distro/cachyos.sh` 的 `systemd-boot-manager`(AUR)。原因:
  该 path unit 假定合并布局 `${ESP}/vmlinuz-*` + `${ESP}/loader/entries/`,本项目
  `lib/disk.sh` 是 `/efi`(纯 ESP)+ `/boot`(XBOOTLDR)双区,内核与 entries
  都在 `/boot`,不在 `/efi`,systemd-boot-manager 会找错位置。装包/配置/
  enable 链路的硬约定:`enable` 在哪台机器都会触发失败,故整体移除比
  conditional 包装更稳。新内核装好后用户需手 `bootctl install` 或复用
  既有的 `install_bootloader` 路径(`lib/disk.sh:108` 已 `--esp-path=/efi
  --boot-path=/boot`)。tests/run.sh 同步:原"装 systemd-boot-manager"
  断言改反向断言"不装"。
- 2026-07-28:设计文档与执行计划定稿;niri/uwsm 建议文档存于旧仓库
  `arch-image-creation/niri-uwsm-notes.md`
- 2026-07-28:全部实现完成。骨架(lib×4 + 主入口)、distro×2、模块×24、
  profiles×2、config 模板、tests/run.sh(132 项,全过)、shellcheck 无 error、
  README × 2。修复:dry-run 免 root、EXTRA/SKIP 逗号字符串归一化、
  local 同行展开顺序(set -u)、done 保留字改名 seen、PROFILES_DIR 未定义
- 2026-07-28:第二轮 4 项改进。mirrorlist 文件名全面对齐官方包
  (original 模式装 pacman-mirrorlist / archcn-mirrorlist-git,--overwrite
  覆盖引导单行文件);ananicy-cpp 仅 CachyOS 装+enable(Arch 上有问题,
  CachyOS 的 cachyos-settings 自带调优);ssh 模块强制 MY_SSH_PUBKEYS 并写
  authorized_keys(密码登录已禁用,无 key 即锁死);确认 systemd-repart
  静态启用无需额外配置(growfs.sh 注释)。tests 148 项全过
- 2026-07-28:内存三选项。mem-zswap(默认,tmpfiles.d 写 zswap 参数——
  已验证 sysctl/modules-load/modprobe.d 对内建 zswap 均不可行,tmpfiles.d
  是 Arch Wiki 推荐写法;zswap 需后备 swap 设备,模块内建 btrfs NOCOW
  swapfile,独立嵌套 subvol /swap,MY_SWAP_SIZE 默认 4G、"0"=不建);
  mem-zram(zram-generator + /etc/systemd/zram-generator.conf,generator
  自动实例化服务);两者 mod_conflicts 互斥;不要 swap 即从 profile 删行。
  镜像默认 --size 20G→32G(容纳 swapfile)。tests 全过
- 2026-07-28:MY_SWAP_SIZE=0 退回 zram(mem-zswap 内回退逻辑);
  镜像改稀疏分配(qemu-img preallocation=off,du 只占真实数据)+
  cleanup 时 fstrim punch 空洞(配合 pacman -Scc 回收宿主机空间)
- 2026-07-29:CachyOS 路径首次端到端实证(14 次镜像 build,全部修复已验证):
  1) cachyos.sh 补 distro_base_packages()——主入口只 source 选中的 distro 文件,
     缺省时 pacstrap 静默退化为裸 base(缺 linux-firmware/efifs/iptables-nft)
  2) pacman_install 固定注入 -S,与 -U/-Syu 冲突(报 only one operation):
     四处 -U 改 chroot_run pacman -U;distro_setup_repos 的 -Syu 直写 pacman -Syu
  3) keyring -U 的 PGP import 询问读 /dev/tty,管道/--noconfirm 均无效:
     先 pacman-key --recv-keys + --lsign-key F3B607488DB35A47(轮换时更新 ID)
  4) arch-chroot 把 chroot /tmp 挂成 tmpfs:sed/仓库段插入改宿主侧直接操作
     $MNT_DIR/etc/pacman.conf;head/tail 拼接插到 [core] 之前(sed r/e 插到行后
     会让 [core] 丢自己的 Include 行,实测)
  5) Architecture = auto 不认 v3/v4 标签:v3→x86_64 x86_64_v3,
     v4/znver4→x86_64 x86_64_v3 x86_64_v4([cachyos] 基础库混有 v3 标签包)
  6) pacman 对同一 host 有错误预算(too many errors from <host>, skipping):
     MY_CACHYOS_MIRRORLIST 含优化路径时自动拆分 opt/base 两个 mirrorlist 文件
  7) distro_base_packages 加 btrfs-progs:内核安装触发 mkinitcpio 的 fsck hook
     找不到 btrfsck 会以 "errors were encountered during the build" 非零退出
  8) pacman_install 的 -Sc 前 rm -rf 缓存目录 download-* 残留(文件或目录,
     否则 -Sc 报 Error reading fd 7)
  9) KERNEL_PKG 契约改全局变量:函数设 KERNEL_PKG+KERNEL_PKGS 不再 echo——
     $(distro_kernel_packages) 的子 shell 会丢掉赋值(install_bootloader 需要)
  10) dev-tools 移除 wakatime(官方仓库没有,仅 AUR wakatime-cli)
  已知问题(已解决,见下条):官方 extra 已下架 nvidia 闭源包;当时误判
  USTC/NJU 未同步 znver4(实际是 znver4 仓库在 x86_64_v4/ 路径下,已纠正)
- 2026-07-29:gpu-nvidia 模块修复:闭源 nvidia 包已下架 → 按 distro 选预编译
  包(arch 用 nvidia-open 绑官方 linux;cachyos 用仓库自带
  $KERNEL_PKG-nvidia-open,按内核变体预编译,不用 DKMS)。znver4 纠正:
  此前"全球删除/国内未同步"结论错误——znver4 仓库位于 x86_64_v4/ 路径
  (wiki:znver4 与 v4 共用 mirrorlist;包 arch 标签同为 x86_64_v4),
  USTC/NJU 均同步。cachyos.sh 修正:znver4 的 archdir=znver4 → x86_64_v4、
  mirrorlist 包 cachyos-v3 → cachyos-v4;cachyos-mirrorlist.china 注释更正,
  v4/znver4 共用该文件。tests 171 项全过
  新增 config/cachyos-mirrorlist.china(NJU/USTC 四行)+ MY_CACHYOS_CDN/
  MY_CACHYOS_MIRRORLIST 配置项;tests 171 项全过;shellcheck 无 error
- 2026-07-29:CachyOS 官方安装器(new-cli-installer)规则吸收:
  1) desktop-kde/desktop-niri 按 DISTRO==cachyos 加 cachyos-kde-settings+
     cachyos-nord-kde-theme-git / cachyos-niri-settings(用户指定)
  2) distro_post_install 加 cachyos-hooks + cachyos-zsh-config(官方:
     用户 shell=zsh 自动装;cachyos-hooks 实测只是 alpm hooks,
     不含 mkinitcpio preset,不解决 fallback)
  3) base.sh 用户组对齐官方:加 rfkill,sys,lp,video,network,storage,audio
  4) mem-zswap 在 swapfile 路径写空 /etc/systemd/zram-generator.conf
     禁掉 cachyos-settings 自带的 zram0(zram-size=ram 会吃全部内存,
     与 swapfile+zswap 冲突;/etc 同名文件优先 /usr/lib)
  5) arch-install 末尾清空 machine-id(dd/克隆多机防撞,首启自动生成)
  6) install_bootloader 的 fallback 条目改为按 initramfs 文件存在性写
     (CachyOS preset 只建 default,原条目指向不存在的 img)
  官方调研备忘:chwd(硬件驱动自动检测)与 gpu-* 显式模块思路相反不吸收;
  官方 btrfs @/@home/... 多 subvol 布局、systemd hook mkinitcpio、
  zswap.enabled=0 内核参数均与本仓设计不同,不动。tests 171 项全过
- 2026-07-29:对照原脚本全文补齐遗漏。清理:random-seed 两处
  (/var/lib/systemd/ 与 /efi/loader/,克隆防撞)+ 镜像缓存 rm -rf 整个
  /var/cache/pacman/pkg(原脚本同款,顺带清 pacstrap/download-* 残留);
  配置:pacman.conf 补 UseSyslog;服务:cli-tools 补 enable atd.service。
  其余逐项核对无缺失(mkinitcpio -P、efifs 驱动、loader entries、
  enable 清单、bootstrap.sh 私活归 hooks)。tests 172 项全过
- 2026-07-29:MY_KERNEL_PARAMS 配置项(lib/disk.sh boot entry options 行尾
  追加,空则不追加)。用途实例:AMD iGPU 跑 LLM 扩 GTT——amdgpu.gttsize 自
  内核 6.13 已废弃(AMD 官方指明改用 ttm.pages_limit;前缀用 ttm. 不用
  amdttm.;页数=GB×262144;built-in 模块只能走 cmdline,modprobe.d 无效)。
  hx370 设 100% 内存=16777216 页(AI Max 395 实测 100% 可用;pages_limit 是
  上限非预留,挤压时走回收/swap)。.gitignore 加 config/config.*.sh
  (各目标机专用配置不提交;config.hx370.sh 曾被误提交已 amend 移除)。
  tests 176 项全过
- 2026-07-29:新增 modules/gpgpu.sh(可选,不进 profiles;参考 Arch Wiki
  GPGPU 页)。MY_GPGPU=amd|nvidia|intel,空=skip,无效=die;--extra-modules
  gpgpu 启用。公共包 ocl-icd+clinfo+opencl-headers;amd=rocm-opencl-runtime+
  rocm-hip-runtime+hip-runtime-amd(LLM 用 HIP;Polaris 及更老需
  ROC_ENABLE_PRE_VEGA=1 自加 environment.d);nvidia=opencl-nvidia+cuda 完整
  toolkit(数 GB);intel=intel-compute-runtime(NEO,Gen12+/独显;Gen8/9/11
  老核显自行用 AUR legacy,不管)。不装虚拟包 opencl-driver(字母序坑,
  同 gpu-intel);与 gpu-* 驱动模块独立不 mod_requires(headless/容器场景
  驱动可来自别处);CachyOS 同步 extra 包名一致无 distro 分支。
  tests 185 项全过,shellcheck 无 error
- 2026-07-29:镜像端到端 qemu 实证(qemu-full+edk2-ovmf;OVMF.4m.fd 在
  /usr/share/edk2/x64/ 不是 ovmf/;-enable-kvm + NVMe 仿真——initramfs
  autodetect 只含宿主硬件模块,IDE/virtio_blk 会找不到根;-vga none 让
  OVMF/sd-boot 控制台回落串口;user-mode net hostfwd 2222→32200)。
  抓到并修复两个必现 bug:
  1) modules/ssh.sh 补 chroot_enable sshdgenkeys.service——sshd.service 只有
     After=sshdgenkeys(仅排序不拉入),不 enable 首启无 host key 必失败;
     刻意不在安装时烘 key(dd/克隆多机 host key 会全相同)
  2) growfs 的 repart Type=linux-root 非法(Failed to parse partition type),
     改 DPS 别名 root——此前"repart 静态启用"只是静态检查,growfs 从未
     真正工作过
  复验(build19 + qemu -snapshot 保镜像 pristine):failed units 空、repart
  Partition table written、根扩到 75G、host key 首启 4 枚、zswap
  Y/zstd/20、swapfile 64G 无 zram、cmdline ttm 参数生效、atd enabled、
  machine-id 首启生成。教训:qemu 读镜像前必须确认构建进程已退出
  (中途 boot 必失败回 OVMF 菜单);pkill -f 的模式会匹配自身命令行
  (用 [x] 括号 trick 防自杀)。tests 186 项全过
- 2026-07-31:默认启用 auditd.service。`modules/auditd.sh` 装 `audit` 包 +
  `chroot_enable auditd.service`,装包与 enable 在同一模块内(符合"装包/enable
  必须同模块"硬约定),不写规则、不装 audispd-plugins、不配转发;`profiles/
  server.conf` 与 `profiles/desktop.conf` 各加入 `auditd` 模块。决策依据:
  `audit-in-dmesg.md` 2026-07-31 本机实测,auditd 取得 kernel audit listener
  (PID 1310716)后,新增 audit 事件不再持续走 kernel printk,`audit.log` 落盘
  正常;在无 rules 状态下 auditd 仍接收 PAM/daemon startup 等事件。该改动改写
  了所有 profile 装出来的机器的安全姿态:会写 `/var/log/audit/audit.log`、
  监听 syscall,需要个性化规则/容量/轮转/failure 策略时请另写配置或
  `--skip-modules auditd` 关闭。`audit-in-dmesg.md` 留作风险审阅文档,未跟踪、
  不进本次 commit。
- 2026-07-29:hx370 真机 dd 后实测修复三则:
  1) repart 只扩分区不扩 btrfs 文件系统(首启日志有 Partition table written
     但无 fs grow 行;第二启分区 930G/fs 75G 时报 No changes,证实它不把
     "分区>fs"视为待办)→ growfs 模块加 systemd-growfs-root.service
     (btrfs filesystem resize max /,改走 fstab x-systemd.growfs 选项(generator 实例模板自带 After=systemd-repart.service))
  2) 多网口只插一根线时未接线口永远 no-carrier,wait-online 默认等全部
     managed 口 2 分钟超时失败 → network-networkd 加 drop-in 改 --any
  3) ESP 默认 fmask=0022,bootctl 报 random-seed world accessible 安全警告
     → mount_target 挂 /efi 加 fmask=0077,dmask=0077(genfstab 会记录进
     fstab;systemd 官方建议 ESP root-only)
  真机(192.168.15.216)已同步部署验证:根 931G、failed 空、ttm 16777216
  生效、11 项关键服务 active。tests 189 项全过
- 2026-08-03:新增 `--device NAME` 设备预设。动机:多台固定硬件设备(hx370
  等)各有固定参数(cputype/distro/内核变体/gpu 模块/MY_KERNEL_PARAMS 的
  ttm GTT 值),此前只能"半个 config 文件 + 记一堆 CLI 参数"。实现:
  prescan_args 先提取 --device/--config(--modules/-h 的提前 exit 一并移入,
  否则 parse_args 后移会让无 config.sh 时 --modules 回归误报缺配置);
  load_device 在 config.sh 之后、parse_args 之前 source devices/NAME.sh
  (NAME 限 [a-z0-9-] 防路径穿越,缺失时 die 并列出可用设备)。叠加顺序:
  内置默认 → config.sh → devices/X.sh → CLI 显式参数。TARGET/FORCE/DRY_RUN
  不可固化;PROFILE 约定每次显式传;--extra/--skip-modules 对设备默认是
  覆盖非追加。devices/*.sh gitignored,模板 devices/example.sh tracked。
  tests 202 项全过(新增 13 项),shellcheck 无 error
- 2026-08-08:multilib 由 distro_setup_repos 启用(arch.sh + cachyos.sh)。
  原在 modules/pacman.sh 启用,意味着 --skip-modules pacman 时 multilib
  仍处于注释状态(默认 pacman.conf 出厂即注释),wine/steam 等 32 位依赖
  装不了,gaming 的 mod_requires pacman 只是兜底关联,其他用到 32 位包
  的场景(用户自加模块)也漏。下放到 distro_setup_repos:arch.sh 由原
  no-op 改为 uncomment `[multilib]`+`Include`;cachyos.sh 在
  `_cachyos_detect_level` 之前同款 sed([multilib] 在 [core] 之后,
  后置插入的 cachyos-* 段不影响)。modules/pacman.sh 删原 sed,留一行
  注释指向 distro。tests 210 项全过(新增 3 项:两 distro 各 +1、
  pacman 模块不再含 uncomment 模式的反向断言),shellcheck 无 error
- 2026-08-17:构建 hx370+kde 镜像(96G dd-able)期间实测修复四类问题:
  1) NJU 在本网络对 .db/.sig 间歇 TLS connect error / 500,触发 pacman
     too-many-errors 放弃整笔事务——影响 pacstrap 与 chroot -Sy。修复:
     `config/hx370-mirrorlist.txt`(gitignored,host mirrorlist 旁路用,
     USTC/aliyun/tuna 等实测可达源)+ `config/hx370.sh` 的 MY_MIRRORLIST_FILE
     指过去;旁路覆盖宿主 /etc/pacman.d/mirrorlist(pacstrap 读宿主 mirrorlist,
     `--mirrorlist config` 仅影响 chroot 内 pacman);`config/cachyos-mirrorlist.china`
     同步剔除 NJU,USTC 升首位 + huaweicloud 二位(aliyun/tuna 不同步 cachyos)
  2) `modules/base.sh` useradd -G docker:docker 模块安装前 docker 组不存在,
     useradd 返回 exit 6(set -e 杀脚本)。修复:docker 在 RESOLVED_MODULES 时
     先 `chroot_run groupadd -f docker`(-f 静默通过,后续 docker 包 install 仍
     装同组,id 恒等)。默认 --mirrorlist copy 走不同事务路径,该错误一直藏着;
     --mirrorlist config 暴露
  3) `modules/pacman.sh` `--mirrorlist config` 下接管 mirrorlist 时报
     "target not found: archcn-mirrorlist-git"——实际包名 archlinuxcn-mirrorlist-git
     (本仓文件路径 `/etc/pacman.d/archcn-mirrorlist` 是对的,只包名错)。
     修复 modules/pacman.sh 行 63 与 tests/run.sh 行 120
  4) hx370 镜像默认 64G swapfile(modules/mem-zswap 内建 btrfs NOCOW,sibling
     subvol /swap);镜像大小 96G 给 rootfs 与装载缓冲;MY_NTP_SERVERS 留空即
     不写入额外 NTP server(chrony 默认 pool)
  经验:1) `--mirrorlist config` 只覆盖 chroot 内 pacman,pacstrap 用宿主 mirrorlist,
     旁路需手动覆盖或预改造宿主文件;2) wrapper 脚本 EXIT trap 在 `exec` 后
     不保留,必须手动 restore 宿主改动;3) archlinuxcn 包名漂移需追仓库公告
  实测镜像:7.6G 占用(96G sparse),1128 包,linux-cachyos-bore 7.1.8,
  cachyos-hooks + cachyos-settings + cachyos-zsh-config 链路完整,fstab 含
  /swap/swapfile 64G + /efi fmask=0077 + repart systemd-growfs-root.service 已 enable
- 2026-08-17:hx370 真机第二轮:dd 后分区扩了、文件系统没扩(930G 分区里
  btrfs 卡在镜像原大小 94.7G,Device slack 835G)。诊断+修复:
  1) 分区侧 OK:systemd-repart + /etc/repart.d/50-root.conf(Type=root)首启
     日志 "94.7G → 930.2G / Partition table written",与 2026-07-29 结论一致
  2) fs 侧两处全断:a) lib/disk.sh 挂载根时带 x-systemd.growfs 指望 genfstab
     记进 fstab——错。内核丢弃 x-*(util-linux 只写 utab),genfstab 只读
     /proc/self/mountinfo(本机 loop+btrfs 实测复现),fstab 根行从未有过该选项,
     systemd-growfs-root.service(fstab-generator 靠它接线)从未被拉起;
     b) repart 配置里的 GrowFileSystem 是不存在的 key(261 man/binary 均无,
     静默忽略),属无效字段
  修复:modules/growfs.sh 装完后直接补写 fstab 根行(awk 追加 x-systemd.growfs
  到 options;注意 genfstab 用空格对齐列宽,$2 是 "/          ",匹配必须 trim;
  补丁带行数+匹配双防护,防 awk 转义错误产出坏 fstab——真机远程修机时踩过);
  repart.d 删无效行;lib/disk.sh 删无效挂载选项+纠正注释。真机端到端验证:
  fstab 补上该选项后 daemon-reload 即见 /run/systemd/generator/-.mount.wants/
  systemd-growfs-root.service + local-fs.target.d/50-order drop-in;手工
  systemctl start 后根 931G(70G used / 860G avail)
  另:该机 KDE autologin 闲置 15 分钟被 powerdevil 自动休眠过一次(SSH 断连),
  与本修复无关;无人值守机器建议 KDE 能源设置关自动休眠或 mask suspend.target
  tests 212 项全过(新增 2 项:growfs 补写 fstab、回归防护 GrowFileSystem)
- 2026-08-21:四个小增项。
  1) modules/gui-apps.sh 加 cachyos-firefox-settings(DISTRO==cachyos 守卫,
     仅 [cachyos] 仓库有该包);
  2) modules/dev-tools.sh 加 opencode;
  3) modules/desktop-kde.sh 在原有 cachyos 守卫块里加 cachyos-themes-sddm;
  4) distro/cachyos.sh 的 distro_post_install 增 systemd-boot-manager
     (新内核装好后自动更新 systemd-boot 条目的路径单元,免手 bootctl)。
     tests/run.sh 加 5 项断言,gui-apps.cachyos-firefox-settings + 守卫、
     dev-tools.opencode、desktop-kde.cachyos-themes-sddm、
     cachyos.systemd-boot-manager。
- 2026-08-21:modules/dev-tools.sh 加 shellcheck([extra] 官方包,非 AUR),
  tests/run.sh 加 1 项断言。
- 2026-08-21:neochat/tokodon 从 desktop-kde 移到 gui-apps。这两个是 KDE
  原生(Kirigami/QML),会拉入 KF6 deps,此前归 desktop-kde;现在作为社交
  客户端归 gui-apps,niri 用户也能用(KF6 deps 自动拉入)。改动:desktop-kde
  的"KDE 专属应用"段删两包,gui-apps 末尾追加;tests/run.sh 同步更新
  原 `gui-apps 不应含 KDE 专属应用` 断言(改成只禁 dolphin/kate 等系统应用,
  不再禁 tokodon),新增 4 项断言(neochat/tokodon 各在/不在的位)
- 2026-08-17:cleanup 追加删除 /var/lib/dbus/machine-id(rm -f,可能是
  /etc/machine-id 的 symlink 或独立副本,不一定存在;dbus 首启时从
  /etc/machine-id 重建)。与既有 machine-id 清空/dd 防撞逻辑同组
