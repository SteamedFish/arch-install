#!/usr/bin/env bash
# modules/gpu-amd.sh — AMD 显卡驱动与监控工具(可选:--extra-modules 或 MY_GPU_MODULES)
# enable 服务:lactd.service(lact 风扇/超频控制守护进程)

mod_install() {
    pacman_install xf86-video-amdgpu mesa vulkan-radeon \
        amdgpu_top amdsmi lact
    chroot_enable lactd.service
}
