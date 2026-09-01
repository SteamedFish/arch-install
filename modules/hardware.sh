#!/usr/bin/env bash
# modules/hardware.sh — 硬件驱动/传感器/电源管理(VPS 用 --skip-modules hardware 跳过)
# enable 服务:irqbalance、smartd、cpupower、fstrim.timer

mod_install() {
    # turbostat 是 x86-only(Intel/AMD PMU,alarm 包页 404),alarm(aarch64)跳过;
    # linux-tools-meta 在 alarm 存在(2026-09-01 实测 200),保留
    local pkgs=(lm_sensors linux-tools-meta htop hwloc
        smartmontools nvme-cli dmidecode cpupower irqbalance)
    [[ ${DISTRO:-arch} == alarm ]] || pkgs+=(turbostat)
    pacman_install "${pkgs[@]}"
    # CPU 调度器:性能优先(桌面/服务器;笔记本省电需求请改 powersave)
    chroot_write_file /etc/default/cpupower <<'EOF'
governor='performance'
EOF
    chroot_enable irqbalance.service smartd.service cpupower.service fstrim.timer
}
