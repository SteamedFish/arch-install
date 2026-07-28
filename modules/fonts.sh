#!/usr/bin/env bash
# modules/fonts.sh — 字体(桌面必需,与 audio 同理须先于 desktop-*)

mod_before() { echo desktop-kde desktop-niri; }

mod_install() {
    pacman_install --asdeps noto-fonts noto-fonts-cjk noto-fonts-emoji \
        noto-fonts-extra ttf-recursive-nerd
}
