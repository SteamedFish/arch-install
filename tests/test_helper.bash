#!/usr/bin/env bash
# tests/test_helper.bash — bats 共享 helpers(随 *.bats 一起加载)
#
# 每个 helper 失败时通过 `return 1` 让 @test 块失败;bats 自动捕获。
# 故意不用 BATS_ASSERT_* 等断言库——本项目偏好零依赖,helpers 内联即可。

# ---- 仓库根(每个 .bats 顶层 cd 到此)----
setup_repo_root() {
    cd "$(dirname "$BATS_TEST_FILENAME")/.." || return 1
}

# ---- bash 语法检查 ----
assert_bash_syntax() {
    local f=$1
    bash -n "$f" || {
        echo "bash -n failed: $f" >&2
        return 1
    }
}

# ---- 文件含/不含(字面/正则)----
# assert_file_contains <file> <pattern>    pattern 用 grep -E
# assert_file_not_contains <file> <pattern>
assert_file_contains() {
    grep -qE -- "$2" "$1" || {
        echo "expected match in $1: $2" >&2
        return 1
    }
}

assert_file_not_contains() {
    ! grep -qE -- "$2" "$1" || {
        echo "unexpected match in $1: $2" >&2
        return 1
    }
}

# ---- 文件含/不含(字面字符串,不解释为正则)----
# assert_file_contains_literal <file> <literal>
# assert_file_not_contains_literal <file> <literal>
assert_file_contains_literal() {
    grep -qF -- "$2" "$1" || {
        echo "expected literal match in $1: $2" >&2
        return 1
    }
}

assert_file_not_contains_literal() {
    ! grep -qF -- "$2" "$1" || {
        echo "unexpected literal match in $1: $2" >&2
        return 1
    }
}

# ---- 全词匹配(防 dolphin 误命中 dolphins)----
# assert_word_in_file <file> <word>
# assert_word_not_in_file <file> <word>
assert_word_in_file() {
    grep -qw -- "$2" "$1" || {
        echo "expected word '$2' in $1" >&2
        return 1
    }
}

assert_word_not_in_file() {
    ! grep -qw -- "$2" "$1" || {
        echo "unexpected word '$2' in $1" >&2
        return 1
    }
}

# ---- 目录递归含/不含(供反向断言)----
# assert_dir_no_match <dir> <regex>        dir 下任何文件都不应命中
assert_dir_no_match() {
    ! grep -rEn -- "$2" "$1" | grep -v '^Binary' || {
        echo "unexpected match in $1: $2" >&2
        return 1
    }
}

# ---- 多目录反向断言(共享 regex)----
# assert_dirs_no_match <dir1> [<dir2>...] < -- <regex>
assert_dirs_no_match() {
    local dirs=() regex=
    while [[ $# -gt 0 ]]; do
        [[ $1 == -- ]] && { regex=$2; break; }
        dirs+=("$1"); shift
    done
    for d in "${dirs[@]}"; do
        if grep -rEn -- "$regex" "$d" 2>/dev/null | grep -v '^Binary' | grep -q .; then
            echo "unexpected match in $d: $regex" >&2
            grep -rEn -- "$regex" "$d" 2>/dev/null | grep -v '^Binary' >&2
            return 1
        fi
    done
}

# ---- 在某行起首匹配(如 pacman_install 行)----
# assert_line_match <file> <regex>
assert_line_match() {
    grep -qE -- "$2" "$1" || {
        echo "expected line match in $1: $2" >&2
        return 1
    }
}

# assert_line_no_match <file> <regex>
assert_line_no_match() {
    ! grep -E -- "$2" "$1" || {
        echo "unexpected line match in $1: $2" >&2
        return 1
    }
}

# ---- dry-run 包装 ----
# run_dry_run <args...>         stdout 进 $DRYRUN_OUT,exit 0
run_dry_run() {
    DRYRUN_OUT=$(./arch-install --target /tmp/x.img --dry-run "$@" 2>&1) || {
        echo "dry-run failed: $*" >&2
        echo "$DRYRUN_OUT" >&2
        return 1
    }
    export DRYRUN_OUT
}

# ---- 临时 config.sh(给 dry-run 用)----
ensure_dryrun_config() {
    if [[ ! -f config/config.sh ]]; then
        cat >config/config.sh <<'EOF'
MY_USERNAME="dryrun-test"
MY_SSH_PUBKEYS=("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDummyKeyForDryRunOnly dryrun@test")
EOF
        DRYRUN_CLEANUP_CONFIG=1
        export DRYRUN_CLEANUP_CONFIG
    fi
}

# ---- 临时设备文件清理(bats teardown 调用)----
cleanup_test_device() {
    rm -f devices/testdev.sh
}

# ---- 字符串包含 ----
# assert_str_contains <haystack> <needle>
assert_str_contains() {
    [[ $1 == *"$2"* ]] || {
        echo "expected substring: $2" >&2
        echo "got: $1" >&2
        return 1
    }
}

# ---- 字符串不含 ----
# assert_str_not_contains <haystack> <needle>
assert_str_not_contains() {
    [[ $1 != *"$2"* ]] || {
        echo "unexpected substring: $2" >&2
        echo "got: $1" >&2
        return 1
    }
}
