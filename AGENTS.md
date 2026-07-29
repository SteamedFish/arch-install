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
- [ ] 镜像端到端 qemu 验证(需手动:构建镜像 → OVMF 启动 → 检查扩容/服务)
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
  已知问题:官方 extra 已下架 nvidia 闭源包(只剩 nvidia-open*),gpu-nvidia
  模块待改;USTC/NJU 均未同步 znver4 树(空目录),国内用 v4 仓库
- 2026-07-29:gpu-nvidia 模块修复:nvidia → nvidia-open-dkms(官方仓库 2026-07
  下架闭源 nvidia 包;DKMS 变体配合已装的内核 headers,通吃 linux/linux-cachyos,
  预编译 nvidia-open 只绑 Arch 官方内核)。znver4 调查结论:CachyOS 官方源
  (us.cachyos.org /repo/)已整体删除 znver4 树(404),x86_64/v3/v4 均正常,
  全球 24 个镜像无一提供 znver4 —— v4 路线是唯一选择,--cachyos-repo znver4
  实际已不可用(上游废弃,非镜像同步问题)
  新增 config/cachyos-mirrorlist.china(NJU/USTC 四行)+ MY_CACHYOS_CDN/
  MY_CACHYOS_MIRRORLIST 配置项;tests 171 项全过;shellcheck 无 error
