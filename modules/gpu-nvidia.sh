#!/usr/bin/env bash
# modules/gpu-nvidia.sh — NVIDIA 闭源驱动(可选)
# 注意:与 gpu-amd 不互斥(双显卡笔记本常见);KDE/niri 的 Wayland 下 nvidia
#       需要 nvidia_drm.modeset=1,如有需要请在 bootctl entry 或钩子中加

mod_install() {
    pacman_install nvidia nvidia-utils nvidia-settings nvtop
}
