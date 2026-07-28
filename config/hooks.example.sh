#!/usr/bin/env bash
# config/hooks.example.sh — 私活钩子模板(cp 为 hooks.sh 后修改;hooks.sh 不进 git)
# 可用接口:log/info/warn/die、chroot_run、pacman_install、chroot_write_file、
#           chroot_enable、$MNT_DIR、全部 MY_* 变量
# 定义任意以下函数,存在即被主流程调用:

# 模块全部装完后调用。示例:拷私钥、clone dotfiles、yadm bootstrap
hook_post_install() {
    :
}

# 首启一次性 unit 示例(MY_SECRETS_MODE=firstboot 时可参考):
# 生成 /etc/systemd/system/firstboot-secrets.service + /usr/local/bin/firstboot-secrets.sh,
# 从 $MY_BACKUP_TARGET rsync 回 ~/.ssh ~/.gnupg 后 yadm clone,成功则 self-disable。
