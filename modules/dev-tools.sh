#!/usr/bin/env bash
# modules/dev-tools.sh — 开发工具:git 生态、编辑器、格式化/构建、LSP/formatter
# 分类边界:dotfiles(git-crypt/yadm)在 base、security;密码管理(pass/passff-host)在 security

mod_install() {
    # 无 wakatime:官方仓库没有(仅 AUR 有 wakatime-cli),本安装器不用 AUR
    pacman_install git git-delta github-cli \
        neovim vim cmake shellcheck \
        python-black patch parallel \
        opencode
    # opencode 内置 LSP/formatter 支持的工具(全官方仓库,选型见 CHANGELOG 2026-08-30)
    pacman_install bash-language-server lua-language-server \
        ruff uv biome yaml-language-server \
        pyright gopls rust-analyzer
}
