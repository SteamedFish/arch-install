#!/usr/bin/env bats
# tests/profile_contract.bats — section 3: profile 引用的模块必须存在(desktop 占位符除外)
# 每个模块一行 grep + 文件存在检查,失败精确定位
# 锚点宽松:接 `[a-z-]+ 行,允许前导空白和尾注释(mem-zswap/auditd 之类带注释的也匹配)
load test_helper
setup() { setup_repo_root; }

# helper: 模块在 profile 里出现且模块文件存在
# assert_module_in_profile <profile> <module>
assert_module_in_profile() {
    grep -qE "^[[:space:]]+$2[[:space:]]*(#|$)" "$1" || {
        echo "missing in $1: $2" >&2
        return 1
    }
    [[ -f "modules/$2.sh" ]] || {
        echo "missing modules/$2.sh" >&2
        return 1
    }
}

# ---- server profile ----
@test "server: base" {                assert_module_in_profile profiles/server.conf base; }
@test "server: pacman" {              assert_module_in_profile profiles/server.conf pacman; }
@test "server: growfs" {              assert_module_in_profile profiles/server.conf growfs; }
@test "server: mem-zswap" {           assert_module_in_profile profiles/server.conf mem-zswap; }
@test "server: auditd" {              assert_module_in_profile profiles/server.conf auditd; }
@test "server: ssh" {                 assert_module_in_profile profiles/server.conf ssh; }
@test "server: cli-tools" {           assert_module_in_profile profiles/server.conf cli-tools; }
@test "server: dev-tools" {           assert_module_in_profile profiles/server.conf dev-tools; }
@test "server: security" {            assert_module_in_profile profiles/server.conf security; }
@test "server: filesystems" {         assert_module_in_profile profiles/server.conf filesystems; }
@test "server: chrony" {              assert_module_in_profile profiles/server.conf chrony; }
@test "server: sysctl" {              assert_module_in_profile profiles/server.conf sysctl; }
@test "server: firewall" {            assert_module_in_profile profiles/server.conf firewall; }
@test "server: network-networkd" {    assert_module_in_profile profiles/server.conf network-networkd; }
@test "server: hardware" {            assert_module_in_profile profiles/server.conf hardware; }
@test "server: monitoring" {          assert_module_in_profile profiles/server.conf monitoring; }
@test "server: docker" {              assert_module_in_profile profiles/server.conf docker; }
@test "server: backup" {              assert_module_in_profile profiles/server.conf backup; }

# ---- desktop profile ----
@test "desktop: base" {                assert_module_in_profile profiles/desktop.conf base; }
@test "desktop: pacman" {              assert_module_in_profile profiles/desktop.conf pacman; }
@test "desktop: growfs" {              assert_module_in_profile profiles/desktop.conf growfs; }
@test "desktop: mem-zswap" {           assert_module_in_profile profiles/desktop.conf mem-zswap; }
@test "desktop: auditd" {              assert_module_in_profile profiles/desktop.conf auditd; }
@test "desktop: ssh" {                 assert_module_in_profile profiles/desktop.conf ssh; }
@test "desktop: cli-tools" {           assert_module_in_profile profiles/desktop.conf cli-tools; }
@test "desktop: dev-tools" {           assert_module_in_profile profiles/desktop.conf dev-tools; }
@test "desktop: security" {            assert_module_in_profile profiles/desktop.conf security; }
@test "desktop: filesystems" {         assert_module_in_profile profiles/desktop.conf filesystems; }
@test "desktop: chrony" {              assert_module_in_profile profiles/desktop.conf chrony; }
@test "desktop: sysctl" {              assert_module_in_profile profiles/desktop.conf sysctl; }
@test "desktop: firewall" {            assert_module_in_profile profiles/desktop.conf firewall; }
@test "desktop: network-nm" {          assert_module_in_profile profiles/desktop.conf network-nm; }
@test "desktop: hardware" {            assert_module_in_profile profiles/desktop.conf hardware; }
@test "desktop: monitoring" {          assert_module_in_profile profiles/desktop.conf monitoring; }
@test "desktop: docker" {              assert_module_in_profile profiles/desktop.conf docker; }
@test "desktop: backup" {              assert_module_in_profile profiles/desktop.conf backup; }
@test "desktop: desktop 占位符" {        grep -qE '^[[:space:]]+desktop[[:space:]]*(#|$)' profiles/desktop.conf; }

# ---- 通用检查: profile 内每个 [a-z-]+ 行(去注释)必须有对应模块文件(desktop 占位符除外)----
@test "所有 profile 行引用的模块文件都存在(desktop 占位符除外)" {
    for p in profiles/*.conf; do
        while read -r line; do
            [[ $line =~ ^[a-z-]+$ ]] || continue
            [[ $line == desktop ]] && continue
            [[ -f "modules/$line.sh" ]] || { echo "$p 缺 modules/$line.sh" >&2; return 1; }
        done < <(grep -v '^\s*#' "$p")
    done
}
