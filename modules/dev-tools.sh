#!/usr/bin/env bash
# modules/dev-tools.sh — 开发工具:git 生态、编辑器、格式化/构建、LSP/formatter
# 分类边界:dotfiles(git-crypt/yadm)在 base、security;密码管理(pass/passff-host)在 security

mod_install() {
    # 无 wakatime:官方仓库没有(仅 AUR 有 wakatime-cli),本安装器不用 AUR
    # opencode/shellcheck 在 alarm(aarch64)仓库不存在(包数据库比对确认缺失;
    # shellcheck 拖 haskell 栈,aarch64 未构建),alarm 跳过
    local pkgs=(git git-delta github-cli \
        neovim vim cmake \
        python-black patch parallel)
    [[ ${DISTRO:-arch} == alarm ]] || pkgs+=(opencode shellcheck)
    pacman_install "${pkgs[@]}"
    # opencode 内置 LSP/formatter 支持的工具(全官方仓库,选型见 CHANGELOG 2026-08-30)
    pacman_install bash-language-server bats lua-language-server \
        ruff uv yaml-language-server \
        pyright gopls rust-analyzer
    # biome 同缺(alarm 各仓库 + archlinuxcn aarch64 均无),alarm 跳过
    [[ ${DISTRO:-arch} == alarm ]] || pacman_install biome
}
