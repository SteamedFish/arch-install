# arch-install 实现计划(框架式)

> 日期:2026-07-28
> 详细设计:`docs/plans/2026-07-28-arch-install-design.md`(已确认)
> 本文件为执行框架 + 后续追加决策;与设计文档冲突时以本文件为准。

## 追加设计决策(2026-07-28 用户确认)

1. **GPU 驱动拆模块**:`gpu-amd` / `gpu-nvidia` / `gpu-intel`,desktop profile 不默认包含,
   由 `--extra-modules` 或 config 变量 `MY_GPU_MODULES` 选择。
2. **gui-apps 模块**:非必须 GUI 应用(tokodon firefox telegram-desktop element-desktop
   emacs discord flameshot okular gwenview kate ark smplayer 等)独立成 `gui-apps` 模块。
3. **pacman cache 清理**:VM 镜像空间有限。`pacman_install` 封装(lib/chroot.sh)
   每次装完执行 `pacman -Sc --noconfirm`;最终 cleanup 阶段镜像模式再 `pacman -Scc`。
4. **安装顺序敏感(pacman 字母序坑)**:pacman 对 `a or b` 虚拟依赖按字母序选第一个,
   必须先装更优实现。已知规则:
   - `audio`(pipewire 全家)必须先于 `desktop-kde`/`desktop-niri`(否则 KDE 拉 pulseaudio)
   - 通用机制:模块可声明 `mod_before()`(在指定模块之前执行);resolver 拓扑排序时尊重。
   - 遇到冲突包/要卸载包 = 顺序出错信号:调整顺序并在模块文件注释记录原因。

## 模块接口(最终版)

`modules/<name>.sh` 被 source,可定义:

```bash
mod_requires()  { :; }   # echo 依赖模块(空格分隔),自动先装
mod_conflicts() { :; }   # echo 互斥模块
mod_before()    { :; }   # echo 本模块必须先于其执行的模块(顺序敏感时用,须注释原因)
mod_install()   { ... }  # 装包 + 写配置 + enable 服务(经 lib/chroot.sh 封装)
```

模块文件头注释:功能 / 依赖的 MY_* 变量 / enable 的服务 / 顺序敏感说明。
模块内零硬编码个人信息;MY_* 为空则 skip 并打日志。

## 执行顺序

`lib/modules.sh` 解析:profile MODULES ± extra/skip → requires 闭包 → conflicts 校验 →
拓扑排序(默认按固定优先级表:`base pacman growfs ssh audio fonts ime` 靠前,
`desktop-*` 靠后;`mod_before` 边覆盖) → 依次 `mod_install`。

## 任务分解

| # | 任务 | 文件 | 负责 |
|---|---|---|---|
| 1 | 仓库骨架 + 本文档 + AGENTS.md | .gitignore AGENTS.md | 主线 |
| 2 | 核心库:日志/依赖检查/参数解析 | lib/common.sh arch-install | 主线 |
| 3 | 磁盘/镜像 + chroot 封装 + 模块解析器 + 测试 | lib/disk.sh lib/chroot.sh lib/modules.sh tests/run.sh | 子代理 A |
| 4 | distro 抽象 | distro/arch.sh distro/cachyos.sh | 子代理 B |
| 5 | 核心模块 | modules/base.sh growfs.sh ssh.sh | 主线 |
| 6 | server 模块批 1 | pacman cli-tools dev-tools security filesystems chrony sysctl firewall | 子代理 C |
| 7 | server 模块批 2 + GPU | network-networkd network-nm hardware monitoring docker virt backup gpu-amd gpu-nvidia gpu-intel | 子代理 D |
| 8 | desktop 模块批 | audio fonts ime bluetooth desktop-niri desktop-kde gui-apps gaming | 子代理 E |
| 9 | profiles + config 模板 + hooks | profiles/*.conf config/config.example.sh config/hooks.example.sh | 主线 |
| 10 | README × 2 + 全量 shellcheck/bash -n + dry-run 验证 | README.md README.zh-CN.md | 主线 |

验收:`bash -n` 全部通过;shellcheck 无 error;`--dry-run` 三种 profile 输出正确模块闭包与顺序;
`tests/run.sh` 通过;镜像模式端到端(qemu 启动验证)手动执行并记入 CHANGELOG。

包清单数据源:原脚本 `/home/steamedfish/work/arch-image-creation/create-os-image.sh`
(server 包 150–166 行,desktop 包 782–808 行),按设计文档第 3.2 节模块表拆分。
