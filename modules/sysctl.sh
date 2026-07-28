#!/usr/bin/env bash
# modules/sysctl.sh — 内核/网络调优 + systemd 资源限制
# sysctl 文件为个人多年调优沉淀(从原脚本移植,改名 99-my.conf),
# 注释掉的备选项保留作参考。enable 服务:systemd-oomd.service

mod_install() {
    chroot_write_file /etc/sysctl.d/99-my.conf <<'SYSCTL'
########## Kernel ##########

# controls the System Request debugging functionality of the kernel
# default: 16
kernel.sysrq = 0

# disables kexec as it can be used to livepatch the running kernel
# default: 0
kernel.kexec_load_disabled = 1

########## Virtualization ##########

# improve mmap ASLR effectiveness
# default: 28
vm.mmap_rnd_bits = 32
# default: 8
vm.mmap_rnd_compat_bits = 16

########## Networking ##########

# increase the maximum length of processor input queues
# default: 1000
net.core.netdev_max_backlog = 250000

# increase TCP max buffer size settable using setsockopt()
# default: 212992
net.core.rmem_default = 8388608
# default: 212992
net.core.wmem_default = 8388608
# default: 212992
net.core.rmem_max = 536870912
# default: 212992
net.core.wmem_max = 536870912

########## IPv4 Networking ##########

# enable BBR congestion control
# default: cubic
net.ipv4.tcp_congestion_control = bbr

# log packets with impossible addresses to kernel log
# default: 0
net.ipv4.conf.default.log_martians = 1
# default: 0
net.ipv4.conf.all.log_martians = 1

# mitigate TIME-WAIT Assassination hazards in TCP
# refer to RFC1337
# default: 0
net.ipv4.tcp_rfc1337 = 1

# increase system IP port limits
# default: 32768 60999
net.ipv4.ip_local_port_range = 1024 65535

# SSR could impact TCP's performance on a fixed-speed network (e.g., wired)
#   but it could be helpful on a variable-speed network (e.g., LTE)
# uncomment this if you are on a fixed-speed network
# default: 1
net.ipv4.tcp_slow_start_after_idle = 0

# enabling MTU probing helps mitigating PMTU blackhole issues
# this may not be desirable on congested networks
# default: 0
net.ipv4.tcp_mtu_probing = 1

# increase memory thresholds to prevent packet dropping
# the maximum buffer size is 536870912 bytes (512 MiB)
# default: 4096 131072 6291456
net.ipv4.tcp_rmem = 8192 262144 536870912
# default: 4096 16384 4194304
net.ipv4.tcp_wmem = 4096 16384 536870912

# reduce the maximum window size to 128 MiB to reduce TCP receive queue collapse
#   (see https://blog.cloudflare.com/optimizing-tcp-for-high-throughput-and-low-latency)
#default: 1
net.ipv4.tcp_adv_win_scale = -2

########## Misc ##########

# default: 4096
net.core.somaxconn = 8192
# default: 1
net.ipv4.tcp_fastopen = 3
# default: 4096
net.ipv4.tcp_max_syn_backlog = 8192
# default: 120
net.ipv4.tcp_keepalive_time = 60
# default: 75
net.ipv4.tcp_keepalive_intvl = 10
# default: 9
net.ipv4.tcp_keepalive_probes = 6
#net.core.default_qdisc = cake
net.core.default_qdisc = fq_codel
SYSCTL

    chroot_write_file /etc/systemd/system.conf.d/limits.conf <<'EOF'
[Manager]
DefaultTasksMax=infinity
DefaultLimitCPU=infinity
DefaultLimitFSIZE=infinity
DefaultLimitDATA=infinity
DefaultLimitSTACK=infinity
DefaultLimitCORE=infinity
DefaultLimitRSS=infinity
DefaultLimitNOFILE=infinity
DefaultLimitAS=infinity
DefaultLimitNPROC=infinity
DefaultLimitMEMLOCK=infinity
DefaultLimitLOCKS=infinity
DefaultLimitSIGPENDING=infinity
DefaultLimitMSGQUEUE=infinity
DefaultLimitRTPRIO=infinity
DefaultLimitRTTIME=infinity
EOF
    chroot_enable systemd-oomd.service
}
