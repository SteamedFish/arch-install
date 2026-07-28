#!/usr/bin/env bash
# lib/common.sh — 日志、依赖检查、确认、通用工具
# 所有函数在 root 下运行(主入口已校验 EUID)

# ---- 日志 ----
log()  { printf '\033[1;34m[*]\033[0m %s\n' "$*"; }
info() { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

# ---- 依赖检查(需求 5)----
# check_deps cmd1 cmd2 ...  缺失时打印 pacman 安装提示并退出
check_deps() {
    local missing=() cmd
    for cmd in "$@"; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    ((${#missing[@]} == 0)) && return 0
    warn "缺少依赖命令: ${missing[*]}"
    warn "请先安装(Arch): sudo pacman -S --needed ${missing[*]}"
    warn "(部分命令所属包名可能与命令名不同,如 qemu-img→qemu-img/qemu-base)"
    exit 1
}

# ---- 交互确认(--force 或 DRY_RUN 时跳过)----
# confirm "描述文字" || die "已取消"
confirm() {
    local prompt=$1
    [[ ${FORCE:-0} == 1 ]] && return 0
    local reply
    read -r -p "$prompt [yes/N] " reply
    [[ $reply == "yes" ]]
}

# ---- CPU 厂商 → 微码包名前缀(intel/amd)----
detect_cputype() {
    if grep -q GenuineIntel /proc/cpuinfo; then
        echo intel
    else
        echo amd
    fi
}

# ---- 逗号分隔列表 → 空格分隔 ----
csv_to_list() { tr ',' ' ' <<<"$1"; }
