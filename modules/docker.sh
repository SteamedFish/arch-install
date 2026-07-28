#!/usr/bin/env bash
# modules/docker.sh — docker + rootless 生态
# subuid/subgid 映射在 security 模块;docker 组成员由 base 模块在 useradd 时处理
# 不 enable docker.service:日常用 rootless(用户态 systemctl --user enable docker)

mod_install() {
    pacman_install docker docker-compose nerdctl docker-rootless-extras podman podlet
    pacman_install --asdeps fuse-overlayfs pigz docker-buildx passt
}
