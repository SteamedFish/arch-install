#!/usr/bin/env bash
# modules/dev-tools.sh — 开发工具:git 生态、编辑器、格式化/构建

mod_install() {
    # 无 wakatime:官方仓库没有(仅 AUR 有 wakatime-cli),本安装器不用 AUR
    pacman_install git git-crypt git-delta github-cli \
        neovim vim cmake \
        python-black pass passff-host patch parallel yadm
}
