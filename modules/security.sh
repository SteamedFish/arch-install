#!/usr/bin/env bash
# modules/security.sh — sudo 配置、subuid/subgid(rootless 容器前提)、密码/加密工具
# 读取变量:MY_USERNAME
# 分类边界:pass/passff-host/git-crypt 归此(设计文档 §3.2:security = pass/git-crypt/gnupg 相关)

mod_install() {
    pacman_install sudo
    # 密码管理(gpg 被 pass 拉入)与 git 仓库加密;passff-host 是 pass 的浏览器扩展宿主
    pacman_install pass passff-host git-crypt
    chroot_write_file /etc/sudoers.d/myconf <<'EOF'
## wheel 组免密 sudo(个人机器,按需收紧)
%wheel ALL=(ALL:ALL) NOPASSWD: ALL
%sudo   ALL=(ALL:ALL) ALL
EOF
    chmod 440 "${MNT_DIR}/etc/sudoers.d/myconf"

    # rootless docker/podman 需要 subuid/subgid 映射
    chroot_write_file /etc/subuid <<<"${MY_USERNAME}:231072:65536"
    chroot_write_file /etc/subgid <<<"${MY_USERNAME}:231072:65536"
}
