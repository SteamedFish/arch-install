#!/usr/bin/env bash
# modules/network-networkd.sh — systemd-networkd(server/VPS 用;桌面用 network-nm)
# enable 服务:systemd-networkd.service。
# systemd-resolved:disable service 让其不持久运行;反向 enable 它 [Install]
# Also= 联动的 varlink/monitor socket,这样 networkd 通过 D-Bus 推 DNS 时
# socket 按需拉起 resolved,resolved 写 stub-resolv.conf 后退出,见 mod_install。

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
    # 多网口机器只插一根线时,未接线的口永远 no-carrier/configuring,
    # wait-online 默认等全部 managed 口会 2 分钟超时失败(hx370 eth0/eth1 实测);
    # --any 改为任一口 routable 即成功
    chroot_write_file /etc/systemd/system/systemd-networkd-wait-online.service.d/any.conf <<'EOF'
[Service]
ExecStart=
ExecStart=/usr/lib/systemd/systemd-networkd-wait-online --any
EOF
    chroot_enable systemd-networkd.service
    # systemd-resolved:disable service 让其不持久运行,但 [Install] 段含
    # Also=systemd-resolved-varlink.socket systemd-resolved-monitor.socket
    # (systemd >= 254 实测),`systemctl disable` 会通过 Also= 联动 socket
    # 一起禁掉——此时 networkd 经 D-Bus 推 DNS 无人接收,/run/systemd/resolve/
    # 永远不存在,/etc/resolv.conf 留空模板,系统无 DNS(opi5plus ARM 实测)。
    # 反向 enable 这两个 socket:D-Bus 第一次调用时 socket 按需拉起 resolved,
    # resolved 写 /run/systemd/resolve/stub-resolv.conf 后退出,无持久进程。
    # 顺序敏感:disable 必须在 enable 之前(否则 enable 会被 disable 再次联动禁掉)。
    chroot_run systemctl disable systemd-resolved.service
    chroot_run systemctl enable systemd-resolved-varlink.socket systemd-resolved-monitor.socket
    # /etc/resolv.conf 是 filesystem 包自带的占位文件(只有注释、零 nameserver),
    # symlink 到 stub-resolv.conf 后,resolved 启动时会自动写入 nameserver。
    # ln -sf 在源不存在时也能建 symlink(/run/systemd/resolve/ 首启才出现)。
    # 必须宿主侧操作:arch-chroot 会把宿主 /etc/resolv.conf bind 进 chroot,
    # chroot 内替换它报 EBUSY(limine 构建实测);bind 只在 chroot 挂载命名空间
    # 内,宿主侧 $MNT_DIR 下是底层占位文件可自由替换。
    ln -sf /run/systemd/resolve/stub-resolv.conf "$MNT_DIR/etc/resolv.conf"
}

mod_conflicts() { echo network-nm; }
