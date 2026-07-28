#!/usr/bin/env bash
# modules/hardware.sh — 硬件驱动/传感器/电源管理(VPS 用 --skip-modules hardware 跳过)
# enable 服务:irqbalance、smartd、cpupower、fstrim.timer

mod_install() {
    pacman_install lm_sensors linux-tools-meta htop hwloc \
        smartmontools nvme-cli turbostat dmidecode cpupower irqbalance
    # CPU 调度器:性能优先(桌面/服务器;笔记本省电需求请改 powersave)
    chroot_write_file /etc/default/cpupower <<'EOF'
governor='performance'
EOF
    chroot_enable irqbalance.service smartd.service cpupower.service fstrim.timer
}
