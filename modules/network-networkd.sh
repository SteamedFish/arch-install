#!/usr/bin/env bash
# modules/network-networkd.sh — systemd-networkd(server/VPS 用;桌面用 network-nm)
# enable 服务:systemd-networkd.service;disable:systemd-resolved.service(与原脚本一致)

mod_install() {
    chroot_write_file /etc/systemd/network/00-ether.link <<'EOF'
[Match]
Type=ether

[Link]
RxChannels=max
TxChannels=max
OtherChannels=max
CombinedChannels=max
AutoNegotiationFlowControl=yes
RxBufferSize=max
TxBufferSize=max
WakeOnLan=on
EOF
    chroot_write_file /etc/systemd/network/00-dhcp.network <<'EOF'
[Match]
Type=ether

[Network]
DHCP=yes
EOF
    chroot_enable systemd-networkd.service
    chroot_run systemctl disable systemd-resolved.service
}

mod_conflicts() { echo network-nm; }
