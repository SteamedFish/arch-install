#!/usr/bin/env bash
# modules/debug.sh — 调试与性能分析工具(可选:--extra-modules debug)
# 不 enable 任何服务,纯工具集

mod_install() {
    pacman_install strace ltrace bpf sysdig lsof gdb perf bpftrace \
        htop iotop nethogs
}
