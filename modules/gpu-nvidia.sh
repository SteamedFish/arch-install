#!/usr/bin/env bash
# modules/gpu-nvidia.sh — NVIDIA 闭源驱动(可选)
# 注意:与 gpu-amd 不互斥(双显卡笔记本常见);KDE/niri 的 Wayland 下 nvidia
#       需要 nvidia_drm.modeset=1,如有需要请在 bootctl entry 或钩子中加
# 2026-07 起官方仓库下架闭源 nvidia 包,只余 nvidia-open*(Turing+ 才可装)。
# 不用 DKMS:arch 的 nvidia-open 预编译绑官方 linux 内核;CachyOS 仓库自带
# 按内核变体预编译的 <KERNEL_PKG>-nvidia-open(与内核同仓库同版本,实测)

mod_install() {
    if [[ ${DISTRO:-arch} == cachyos ]]; then
        pacman_install "$KERNEL_PKG-nvidia-open" nvidia-utils nvidia-settings nvtop
    else
        pacman_install nvidia-open nvidia-utils nvidia-settings nvtop
    fi
}
