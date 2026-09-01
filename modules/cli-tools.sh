#!/usr/bin/env bash
# modules/cli-tools.sh — 常用命令行工具(包从原脚本分类而来,只含纯 CLI)
# 分类边界:编辑器/git 在 dev-tools;硬件监控在 hardware; prometheus 在 monitoring;
#           文件系统工具在 filesystems;yay 在此(dev-tools 的 AUR 操作依赖它)

mod_install() {
    pacman_install yay base-devel \
        dool eza zsh rsync whois man-db wget esh \
        unzip unrar tmux tcpdump strace socat screen psmisc pacman-contrib \
        onefetch fastfetch nmap nethogs mosh lsof lshw lsd lsb-release \
        lrzsz lftp less jq iotop ioping hwdata gzip grc \
        file figlet ethtool dysk dos2unix diffutils \
        curl cscope cpufetch bat aria2 7zip \
        efibootmgr ripgrep ripgrep-all \
        arch-install-scripts bc bind direnv fd ipcalc lsscsi man-pages \
         yt-dlp which trash-cli at bat-extras shfmt lesspipe yq prettier \
         entr mtr zoxide atuin fzf skim difftastic yazi starship inetutils
    # hwinfo/vi 在 alarm(aarch64)各仓库均不存在(x86 中心包;包数据库
    # core/extra/alarm/aur + archlinuxcn aarch64 本地比对确认缺失),alarm 跳过
    [[ ${DISTRO:-arch} == alarm ]] || pacman_install hwinfo vi
    # 原脚本默认 enable atd(at 的守护进程,包在上面的列表里)
    chroot_enable atd.service
}
