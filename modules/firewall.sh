#!/usr/bin/env bash
# modules/firewall.sh — nftables 防火墙(inet filter 单表统一 IPv4/IPv6)
# 读取变量:MY_SSH_PORT(空则 22,与 ssh 模块保持一致)
# enable 服务:nftables.service(Arch 原生开机加载:ExecStart=nft -f /etc/nftables.conf)
# 注:iptables-nft 仍留在 distro_base_packages——docker 运行时依赖 iptables 命令建
#     NAT 链(xtables 兼容层落在 ip 族表,与本模块的 inet 表互不干扰);若从 base
#     移除,后装 docker 时 pacman 会按字母序挑 iptables provider(--noconfirm 下
#     可能选中 legacy)

mod_install() {
    local port=${MY_SSH_PORT:-22}
    pacman_install nftables
    chroot_write_file /etc/nftables.conf <<EOF
#!/usr/bin/nft -f

flush ruleset

table inet filter {
    chain input {
        type filter hook input priority filter; policy drop;
        iifname "lo" accept
        ct state established,related accept
        meta l4proto icmp accept
        meta l4proto ipv6-icmp accept
        ip saddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } accept
        ip6 saddr fc00::/7 accept
        tcp dport $port accept
    }
    chain forward {
        type filter hook forward priority filter; policy accept;
    }
    chain output {
        type filter hook output priority filter; policy accept;
    }
}
EOF
    chroot_enable nftables.service
}
