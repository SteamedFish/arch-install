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
- [ ] anything-sync-daemon(原脚本 TODO,待定)

## CHANGELOG

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
