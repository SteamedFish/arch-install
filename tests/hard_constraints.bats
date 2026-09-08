#!/usr/bin/env bats
# tests/hard_constraints.bats — section 4: 不得硬编码个人信息
# 注:config/ 目录里 .gitignore 的 config.*.sh 含个人数据(本测试本就该跳过),
# 仅检查会被纳入仓库的目录:modules distro lib arch-install profiles
load test_helper
setup() { setup_repo_root; }

@test "无硬编码用户名 steamedfish" {
    assert_dirs_no_match modules distro lib arch-install profiles -- 'steamedfish'
}

@test "无硬编码个人 IP(192.168.1.1/192.168.82.66)" {
    assert_dirs_no_match modules distro lib arch-install profiles -- '192\.168\.1\.1|192\.168\.82\.66'
}

@test "无硬编码 ssh 端口 32200" {
    assert_dirs_no_match modules distro lib arch-install profiles -- '32200'
}
