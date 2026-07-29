#!/usr/bin/env bash
# modules/ssh.sh — openssh 服务
# 读取变量:MY_SSH_PORT(空则 22)、MY_SSH_PUBKEYS(数组,至少一个)
# 由于关闭了密码登录,没有任何公钥意味着装完无法 ssh 登录 → MY_SSH_PUBKEYS 必填
# enable 服务:sshd.service

mod_requires() { echo base; }

mod_install() {
    local port=${MY_SSH_PORT:-22}
    pacman_install openssh
    chroot_write_file /etc/ssh/sshd_config.d/99-my.conf <<EOF
Port $port
PermitRootLogin no
PasswordAuthentication no
EOF
    chroot_enable sshd.service
    # host key 不在安装时生成(ssh-keygen -A 会把同一组 key 烘进镜像,dd/克隆到多台
    # 机器后 host key 全相同);改由 sshdgenkeys.service 首启自动生成——sshd.service
    # 只有 After=sshdgenkeys.service(仅排序不拉入),必须显式 enable
    chroot_enable sshdgenkeys.service

    # set -u 下未声明的数组展开会报错,先兜底
    if ! declare -p MY_SSH_PUBKEYS &>/dev/null; then MY_SSH_PUBKEYS=(); fi
    if ((${#MY_SSH_PUBKEYS[@]} == 0)); then
        if [[ ${DRY_RUN:-0} == 1 ]]; then
            warn "MY_SSH_PUBKEYS 为空(正式安装会报错:密码登录已禁用,必须至少一个公钥)"
            return 0
        fi
        die "MY_SSH_PUBKEYS 未配置:已禁用密码登录,没有公钥将无法 ssh 登录。请在 config.sh 中配置至少一个公钥"
    fi
    log "写入 authorized_keys(${#MY_SSH_PUBKEYS[@]} 个公钥)"
    chroot_run install -d -m 700 -o "$MY_USERNAME" -g "$MY_USERNAME" "/home/$MY_USERNAME/.ssh"
    printf '%s\n' "${MY_SSH_PUBKEYS[@]}" | chroot_write_file "/home/$MY_USERNAME/.ssh/authorized_keys"
    chroot_run chmod 600 "/home/$MY_USERNAME/.ssh/authorized_keys"
    chroot_run chown "$MY_USERNAME:$MY_USERNAME" "/home/$MY_USERNAME/.ssh/authorized_keys"
}
