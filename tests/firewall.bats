#!/usr/bin/env bats
# tests/firewall.bats — section 20: firewall 迁移 nftables(2026-08-23)
# shellcheck disable=SC2314  # bats 中 `! assert_*` 是合法且唯一的最后命令,SC2314 误报
load test_helper
setup() { setup_repo_root; }

@test "firewall 装 nftables 包" {
    assert_file_contains_literal modules/firewall.sh 'pacman_install nftables'
}

@test "firewall 写 /etc/nftables.conf" {
    assert_file_contains_literal modules/firewall.sh '/etc/nftables.conf'
}

@test "nftables 用 inet filter 单表统一 v4/v6" {
    assert_file_contains_literal modules/firewall.sh 'table inet filter'
}

@test "input 链 policy drop" {
    assert_file_contains_literal modules/firewall.sh 'policy drop'
}

@test "放行 established/related" {
    assert_file_contains_literal modules/firewall.sh 'ct state established,related accept'
}

@test "放行 ICMPv6(NDP 必需)" {
    assert_file_contains_literal modules/firewall.sh 'meta l4proto ipv6-icmp'
}

@test "flush ruleset 保证 service 重启幂等" {
    assert_file_contains_literal modules/firewall.sh 'flush ruleset'
}

@test "开机加载走 nftables.service" {
    assert_file_contains_literal modules/firewall.sh 'chroot_enable nftables.service'
}

@test "SSH 端口仍读 MY_SSH_PORT(与 ssh 模块一致)" {
    assert_file_contains modules/firewall.sh 'MY_SSH_PORT'
}

@test "不再写 /etc/iptables 规则文件" {
    ! assert_file_contains_literal modules/firewall.sh '/etc/iptables/'
}

@test "不再 enable iptables/ip6tables 服务" {
    ! grep -qE '(iptables|ip6tables)\.service' modules/firewall.sh
}
