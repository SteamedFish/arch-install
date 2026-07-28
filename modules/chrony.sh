#!/usr/bin/env bash
# modules/chrony.sh — NTP 时间同步
# 读取变量:MY_NTP_SERVERS(额外 server,空格分隔;个人 NTP 服务器放这里)
# enable 服务:chronyd.service、chrony-wait.service

mod_install() {
    pacman_install chrony
    {
        cat <<'EOF'
pool 0.cn.pool.ntp.org iburst
pool 1.cn.pool.ntp.org iburst
pool 2.cn.pool.ntp.org iburst
pool 3.cn.pool.ntp.org iburst
pool ntp1.aliyun.com iburst
pool ntp2.aliyun.com iburst
pool cn.ntp.org.cn iburst
pool time.amazonaws.cn iburst
leapsecmode slew
EOF
        local s
        for s in ${MY_NTP_SERVERS:-}; do
            echo "server $s iburst"
        done
    } >>"${MNT_DIR}/etc/chrony.conf"
    chroot_enable chronyd.service chrony-wait.service
}
