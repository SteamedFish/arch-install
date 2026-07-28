#!/usr/bin/env bash
# modules/firewall.sh — iptables-nft 防火墙(包已在 base 的 distro_base_packages)
# 读取变量:MY_SSH_PORT(空则 22,与 ssh 模块保持一致)
# enable 服务:iptables.service、ip6tables.service

mod_install() {
    local port=${MY_SSH_PORT:-22}
    chroot_write_file /etc/iptables/iptables.rules <<EOF
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]

-A INPUT -p icmp -j ACCEPT
-A INPUT -s 127.0.0.0/8 -j ACCEPT
-A INPUT -s 10.0.0.0/8 -j ACCEPT
-A INPUT -s 172.16.0.0/12 -j ACCEPT
-A INPUT -s 192.168.0.0/16 -j ACCEPT
-A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT

# ssh
-A INPUT -p tcp -m tcp --dport $port -j ACCEPT

-A INPUT -j DROP
COMMIT
EOF
    chroot_write_file /etc/iptables/ip6tables.rules <<EOF
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]

-A INPUT -s ::1/128 -j ACCEPT
-A INPUT -s fc00::/7 -j ACCEPT
-A INPUT -p ipv6-icmp -j ACCEPT
-A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT

# ssh
-A INPUT -p tcp -m tcp --dport $port -j ACCEPT

-A INPUT -j DROP
COMMIT
EOF
    chroot_enable iptables.service ip6tables.service
}
