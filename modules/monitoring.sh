#!/usr/bin/env bash
# modules/monitoring.sh — prometheus exporters
# enable 服务:prometheus-node-exporter、prometheus-smartctl-exporter、prometheus-systemd-exporter

mod_install() {
    pacman_install prometheus-node-exporter prometheus-smartctl-exporter \
        prometheus-systemd-exporter
    chroot_write_file /etc/conf.d/prometheus-node-exporter <<'EOF'
NODE_EXPORTER_ARGS="--collector.buddyinfo --collector.cgroups --collector.cpu_vulnerabilities --collector.drm --collector.drbd --collector.ethtool --collector.interrupts --collector.ksmd --collector.lnstat --collector.logind --collector.meminfo_numa --collector.mountstats --collector.network_route --collector.perf --collector.processes --collector.qdisc --collector.slabinfo --collector.softirqs --collector.sysctl --collector.systemd --collector.tcpstat --collector.wifi --collector.xfrm --collector.zoneinfo"
EOF
    chroot_write_file /etc/conf.d/prometheus-systemd-exporter <<'EOF'
SYSTEMD_EXPORTER_ARGS="--systemd.collector.enable-restart-count --systemd.collector.enable-ip-accounting"
EOF
    chroot_enable prometheus-node-exporter.service \
        prometheus-smartctl-exporter.service prometheus-systemd-exporter.service
}
