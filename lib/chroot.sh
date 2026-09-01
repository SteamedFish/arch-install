#!/usr/bin/env bash
# lib/chroot.sh — arch-chroot 封装。模块只允许通过这些函数操作目标系统。
# 依赖变量:MNT_DIR(由 lib/disk.sh 设置);CHROOT_EMULATE(可选,默认原生)

# qemu-user 静态解释器(构建等级高于宿主 CPU 能力时用)
QEMU_X86_64=${QEMU_X86_64:-/usr/bin/qemu-x86_64-static}
CHROOT_EMU_PATH=${CHROOT_EMU_PATH:-/usr/bin/qemu-x86_64-static}

chroot_run() {
    if [[ ${CHROOT_EMULATE:-0} != 1 ]]; then
        arch-chroot "$MNT_DIR" "$@"
        return
    fi
    # 跨等级构建(仅限 TCG 支持的指令集,如 v2 宿主建 v3 镜像;v4 含
    # AVX-512、qemu TCG 不支持,qemu#2878,distro 层预检已拒绝):
    # chroot 内二进制在宿主 CPU 上会 Illegal instruction,统一经 qemu-user
    # TCG 执行。不用内核 binfmt_misc 路由:
    # x86-64 宿主上注册 x86-64 规则时,qemu 解释器自身也是 x86_64 ELF、
    # 会匹配自己的规则,内核递归解释直至 ELOOP(实测必现)。改用显式前缀:
    # 静态解释器先复制进 chroot,再以「chroot 根内路径」直接 exec——qemu
    # 本身以宿主原生身份运行(不经过任何 binfmt 分发),其内部对子进程
    # execve 的拦截让 chroot 内全部进程(pacman/alpm-hooks 等)都留在模拟
    # 里,宿主全局零影响。QEMU_CPU=max 让 qemu 的 CPUID 如实报告 TCG 全部
    # 支持的 ISA,用户态按 CPUID 分派指令路径,不会执行 TCG 不支持的指令。
    # 注意不用 arch-chroot:它在 qemu 下做嵌套 namespace 不可靠,这里自补
    # proc/sys/dev 挂载(ns 内私有,随 ns 消失,无需清理)
    _chroot_stage_emulator
    [[ -x $QEMU_X86_64 ]] || die "缺少 $QEMU_X86_64。请安装: sudo pacman -S qemu-user-static"
    QEMU_CPU=max unshare -m bash -c '
        set -e
        mnt=$1; emu=$2; shift 2
        mount --make-rprivate /
        mount -t proc proc "$mnt/proc"
        mount --rbind /sys "$mnt/sys"
        mount --rbind /dev "$mnt/dev"
        exec chroot "$mnt" "$emu" "$@"
    ' _ "$MNT_DIR" "$CHROOT_EMU_PATH" "$@"
}

# 把静态解释器放进目标系统(每次调用幂等覆盖,保证与宿主安装的版本一致)
_chroot_stage_emulator() {
    mkdir -p "$MNT_DIR/usr/bin"
    cp -f "$QEMU_X86_64" "${MNT_DIR}${CHROOT_EMU_PATH}"
}

# 模拟模式的早期依赖检查(distro 层确认需要模拟后调用;缺失即 die,
# 此时尚未动磁盘,不会留半成品)
require_emulation_deps() {
    [[ -x $QEMU_X86_64 ]] || die "缺少 $QEMU_X86_64。请安装: sudo pacman -S qemu-user-static"
    command -v unshare &>/dev/null || die "缺少 unshare(util-linux)"
}

# pacman_install [--asdeps] pkg...
# 每次安装后清理旧版本缓存(pacman -Sc)——VM 镜像空间有限,见 plan 追加决策 3
pacman_install() {
    # 网络镜像偶有 10 秒无字节被 pacman 中止(实测 NJU/USTC 均出现),
    # --needed 保证重试幂等;真实错误(如包不存在)重试 3 次后照旧失败
    # alarm(aarch64)经 qemu-user 模拟时 pacman 7.1 下载沙箱必死:qemu-user
    # 不翻译 Landlock/seccomp syscall,而沙箱由出厂 pacman.conf 的
    # DownloadUser=alpm 触发(loop+btrfs chroot 实测必现)。x86 原生 chroot
    # 无此问题。--disable-sandbox 是 CLI flag,不写入目标配置,镜像内仍是
    # 出厂对齐的 DownloadUser=alpm(真机内核有 Landlock,沙箱正常工作)。
    # CHROOT_EMULATE(v2 宿主建 v3 镜像)大概率同病,该路径未实测,不动
    local -a sandbox=()
    [[ ${DISTRO:-arch} == alarm ]] && sandbox=(--disable-sandbox)
    local try
    for try in 1 2 3; do
        chroot_run pacman -S --needed --noconfirm "${sandbox[@]}" "$@" && break
        [[ $try -lt 3 ]] || return 1
        warn "pacman -S 失败(第 $try/3 次),5s 后重试"
        sleep 5
    done
    # 先删中断下载的 download-* 残留(文件或目录都有可能,实测均出现):
    # -Sc 会逐一读取缓存包校验,读到半截的临时文件报 Error reading fd 7
    # 并以非零退出
    rm -rf "$MNT_DIR"/var/cache/pacman/pkg/download-*
    chroot_run pacman -Sc --noconfirm
}

# chroot_write_file /abs/path — 从 stdin 写入目标系统内文件(自动建目录)
chroot_write_file() {
    local path=$1
    mkdir -p "${MNT_DIR}$(dirname "$path")"
    cat >"${MNT_DIR}${path}"
}

# chroot_enable svc1 svc2 ...
chroot_enable() {
    chroot_run systemctl enable "$@"
}
