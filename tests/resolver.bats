#!/usr/bin/env bats
# tests/resolver.bats — section 5: 解析器单测(隔离环境,假模块)
# 验证 mod_requires 闭包、mod_before 拓扑排序、mod_conflicts 检测
load test_helper
setup() {
    setup_repo_root
    local tmpdir
    tmpdir=$(mktemp -d)
    export TMP_TEST_MODULES="$tmpdir"
    mkdir -p "$TMP_TEST_MODULES/modules" "$TMP_TEST_MODULES/profiles"
    cat >"$TMP_TEST_MODULES/modules/a.sh" <<'EOF'
mod_install() { :; }
mod_requires() { echo b; }
EOF
    cat >"$TMP_TEST_MODULES/modules/b.sh" <<'EOF'
mod_install() { :; }
EOF
    cat >"$TMP_TEST_MODULES/modules/c.sh" <<'EOF'
mod_install() { :; }
mod_before() { echo a; }
mod_conflicts() { echo d; }
EOF
    cat >"$TMP_TEST_MODULES/profiles/test.conf" <<'EOF'
MODULES=(a c)
EOF
}
teardown() { rm -rf "$TMP_TEST_MODULES"; }

# ---- requires 闭包 ----
@test "requires 闭包(a→b 自动补全)" {
    run bash -c "
        source lib/common.sh
        SCRIPT_DIR='$TMP_TEST_MODULES'
        DESKTOP=niri EXTRA_MODULES='' SKIP_MODULES='' MY_GPU_MODULES=''
        source lib/modules.sh
        resolve_modules test 2>/dev/null
        echo \"\${RESOLVED_MODULES[*]}\"
    "
    [ "$status" -eq 0 ]
    assert_str_contains "$output" "b"
}

# ---- mod_before 拓扑 ----
@test "mod_before 生效(c 在 a 前)" {
    run bash -c "
        source lib/common.sh
        SCRIPT_DIR='$TMP_TEST_MODULES'
        DESKTOP=niri EXTRA_MODULES='' SKIP_MODULES='' MY_GPU_MODULES=''
        source lib/modules.sh
        resolve_modules test 2>/dev/null
        echo \"\${RESOLVED_MODULES[*]}\"
    "
    [ "$status" -eq 0 ]
    pos_c=$(tr ' ' '\n' <<<"$output" | grep -nx c | cut -d: -f1)
    pos_a=$(tr ' ' '\n' <<<"$output" | grep -nx a | cut -d: -f1)
    [[ -n $pos_c && -n $pos_a && $pos_c -lt $pos_a ]]
}

# ---- conflicts 检测 ----
@test "conflicts 检测(c+d 报错)" {
    cat >"$TMP_TEST_MODULES/modules/d.sh" <<'EOF'
mod_install() { :; }
EOF
    run bash -c "
        source lib/common.sh
        SCRIPT_DIR='$TMP_TEST_MODULES'
        DESKTOP=niri EXTRA_MODULES='d' SKIP_MODULES='' MY_GPU_MODULES=''
        source lib/modules.sh
        resolve_modules test 2>&1 >/dev/null
    "
    [ "$status" -ne 0 ]
    assert_str_contains "$output" "冲突"
}
