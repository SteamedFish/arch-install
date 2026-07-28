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
}
