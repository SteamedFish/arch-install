#!/usr/bin/env bash
# modules/gpu-nvidia.sh — NVIDIA 闭源驱动(可选)
# 注意:与 gpu-amd 不互斥(双显卡笔记本常见);KDE/niri 的 Wayland 下 nvidia
#       需要 nvidia_drm.modeset=1,如有需要请在 bootctl entry 或钩子中加
# 2026-07 起官方仓库下架闭源 nvidia 包,只余 nvidia-open*(Turing+ 才可装)。
# 用 DKMS 变体:安装器两种内核(linux / linux-cachyos)都装了 headers,
# 预编译的 nvidia-open 只绑 Arch 官方内核,在自定义内核上不匹配。

mod_install() {
    pacman_install nvidia-open-dkms nvidia-utils nvidia-settings nvtop
}
