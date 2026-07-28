#!/usr/bin/env bash
# modules/audio.sh — PipeWire 音频栈(桌面必需)
# 顺序说明:pacman 对 "a or b" 形式的依赖按字母序选 a。若 KDE/niri 先于
# pipewire 安装,可能拉入其他音频实现。故本模块必须排在 desktop-* 之前,
# 由 mod_before 声明(解析器拓扑排序保证)。

mod_before() { echo desktop-kde desktop-niri; }

mod_install() {
    pacman_install --asdeps pipewire pipewire-audio pipewire-alsa \
        pipewire-pulse pipewire-jack pipewire-v4l2 wireplumber
}
