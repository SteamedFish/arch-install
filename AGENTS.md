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

- [ ] 核心骨架(lib + 主入口)
- [ ] distro/arch + distro/cachyos
- [ ] 全部模块
- [ ] profiles + config 模板
- [ ] README × 2
- [ ] 镜像端到端 qemu 验证
- [ ] anything-sync-daemon(原脚本 TODO,待定)

## CHANGELOG

- 2026-07-28:设计文档与执行计划定稿;niri/uwsm 建议文档存于旧仓库
  `arch-image-creation/niri-uwsm-notes.md`
