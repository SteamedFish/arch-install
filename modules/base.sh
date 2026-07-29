#!/usr/bin/env bash
# modules/base.sh — 基础系统:pacstrap、fstab、locale、时区、hostname
# 说明:本模块由主入口在挂载后直接执行(不在模块循环内);
# 内核/微码/bootctl 由主入口经 distro 接口另行处理(需在仓库配置后)。

mod_install() {
    log "pacstrap 基础系统"
    # shellcheck disable=SC2046
    pacstrap -K "$MNT_DIR" $(distro_base_packages)

    log "生成 fstab"
    genfstab -U "$MNT_DIR" >>"${MNT_DIR}/etc/fstab"

    log "locale / 时区 / hostname"
    sed -i 's/^#\(en_US.UTF-8 UTF-8\)/\1/; s/^#\(zh_CN.UTF-8 UTF-8\)/\1/' \
        "${MNT_DIR}/etc/locale.gen"
    chroot_run locale-gen
    chroot_write_file /etc/locale.conf <<'EOF'
LANG=en_US.UTF-8
EOF
    ln -sf "/usr/share/zoneinfo/${MY_TIMEZONE:-Asia/Shanghai}" "${MNT_DIR}/etc/localtime"
    chroot_write_file /etc/hostname <<<"${MY_HOSTNAME:-archlinux}"

    # 用户(zsh 由本模块先装,useradd 依赖它;cli-tools 里也有 zsh,--needed 不会重复)
    pacman_install zsh
    # docker 组仅当 docker 模块启用时加入(组不存在会导致 useradd 失败)
    # rfkill/sys/lp/video/network/storage/audio 对齐 CachyOS 官方安装器默认组
    local groups="adm,log,uucp,wheel,users,games,rfkill,sys,lp,video,network,storage,audio"
    [[ " ${RESOLVED_MODULES[*]:-} " == *" docker "* ]] && groups+=",docker"
    groups+="${MY_EXTRA_GROUPS:+,${MY_EXTRA_GROUPS}}"
    chroot_run useradd -m -p '*' -s /usr/bin/zsh -U -G "$groups" "$MY_USERNAME"

    # secrets(完整策略见设计文档第 8 节)
    local mode=${MY_SECRETS_MODE:-}
    [[ -z $mode ]] && { [[ $TARGET_TYPE == image ]] && mode=copy || mode=firstboot; }
    case $mode in
        copy)
            # 仅限镜像或本机物理盘:直接 rsync 宿主机的密钥
            local d
            for d in .ssh .gnupg; do
                if [[ -d $HOME/$d ]]; then
                    rsync -a "$HOME/$d" "${MNT_DIR}/home/${MY_USERNAME}/"
                    chroot_run chown -R "${MY_USERNAME}:${MY_USERNAME}" "/home/${MY_USERNAME}/$d"
                fi
            done
            ;;
        keyfile)
            # https 匿名 clone + git-crypt 对称密钥解锁(仓库公开时可用)
            [[ -n ${MY_DOTFILES_REPO:-} && -n ${MY_GITCRYPT_KEY_FILE:-} ]] \
                || die "MY_SECRETS_MODE=keyfile 需要 MY_DOTFILES_REPO 与 MY_GITCRYPT_KEY_FILE"
            pacman_install git git-crypt yadm
            install -Dm600 "$MY_GITCRYPT_KEY_FILE" \
                "${MNT_DIR}/home/${MY_USERNAME}/.gitcrypt-key"
            chroot_run chown "${MY_USERNAME}:${MY_USERNAME}" "/home/${MY_USERNAME}/.gitcrypt-key"
            chroot_run su - "$MY_USERNAME" -c \
                "yadm clone '${MY_DOTFILES_REPO}' --no-bootstrap && yadm git-crypt unlock ~/.gitcrypt-key"
            ;;
        firstboot)
            # 不落任何私钥进镜像;由 hooks.sh 生成首启一次性 unit 从备份恢复(见 hooks.example.sh)
            info "secrets 模式 firstboot:请在 config/hooks.sh 的 hook_post_install 中生成首启恢复 unit"
            ;;
        none) ;;
        *) die "未知 MY_SECRETS_MODE: $mode(copy|firstboot|keyfile|none)" ;;
    esac
}
