#!/usr/bin/env bash
# modules/gpu-intel.sh — Intel 核显驱动与硬件编解码(可选)
# 不装 opencl-driver:它是虚拟包,pacman --noconfirm 会按字母序选第一个
# 提供者,不一定是你想要的(顺序坑,见 plan 追加决策 4)

mod_install() {
    pacman_install mesa vulkan-intel intel-media-driver libva-intel-driver \
        onevpl-intel-gpu
}
