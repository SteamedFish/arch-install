#!/usr/bin/env bash
# modules/dev-tools.sh — 开发工具:git 生态、编辑器、格式化/构建

mod_install() {
    pacman_install git git-crypt git-delta github-cli \
        neovim vim cmake \
        python-black pass passff-host patch parallel yadm wakatime
}
