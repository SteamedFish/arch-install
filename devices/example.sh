#!/usr/bin/env bash
# devices/example.sh — 设备预设模板
# 用法:cp devices/example.sh devices/<设备名>.sh 然后按需取消注释
# (devices/*.sh 已 gitignore,本模板是唯一 tracked 文件)
#
# 叠加顺序:内置默认值 → config/config.sh → 本文件 → CLI 显式参数(后者覆盖前者)
# 本文件在 config.sh 之后 source,可同时固化 CLI 参数默认值与覆盖 MY_* 变量。
#
# 不可固化:TARGET / FORCE / DRY_RUN(误刷风险,必须每次显式指定)
# 约定:PROFILE 不写在这里(要不要 desktop 属于"不固定"决策,每次 --profile 显式传)
# 注意:--extra-modules / --skip-modules 对设备默认值是【覆盖】不是追加,
#       CLI 里想保留设备值需写全。

# ---- 发行版与内核 ----
#DISTRO=cachyos                  # arch | cachyos
#CACHYOS_KERNEL=bore             # default|bore|bmq|lts|server|hardened|rt-bore|eevdf|rc
#CACHYOS_REPO=znver4             # auto|v3|v4|znver4

# ---- 硬件 ----
#CPUTYPE=amd                     # auto|amd|intel(异构构建时固定目标机 CPU)
#DESKTOP=niri                    # niri|kde(仅 --profile desktop 时生效)

# ---- 模块增减(CLI 传入时整体覆盖,不是追加)----
#EXTRA_MODULES="gpu-amd"         # 空格分隔,并入 extra-modules
#SKIP_MODULES=""                 # 空格分隔

# ---- 其他 CLI 默认值 ----
#SIZE=32G                        # 镜像大小(物理盘忽略)
#MIRRORLIST=copy                 # copy|original|reflector|config

# ---- MY_* 变量(覆盖 config.sh 同名值;全部 MY_* 均可在此设置)----
#MY_HOSTNAME=hx370
# AMD iGPU 跑 LLM 扩 GTT 实例(amdgpu.gttsize 已废弃,用 ttm.pages_limit;
# 页数=GB×262144;AI Max 395 实测 100% 内存可用):
#MY_KERNEL_PARAMS="ttm.pages_limit=16777216 ttm.page_pool_size=16777216"
