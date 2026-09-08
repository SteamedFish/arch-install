#!/usr/bin/env bats
# tests/dryrun.bats — section 6: dry-run 端到端(无需 root)
load test_helper
setup() {
    setup_repo_root
    ensure_dryrun_config
}
teardown() {
    if [[ ${DRYRUN_CLEANUP_CONFIG:-0} == 1 ]]; then
        rm -f config/config.sh
    fi
}

@test "dry-run server" {
    ./arch-install --target /tmp/x.img --profile server --dry-run >/dev/null 2>&1
}

@test "dry-run desktop niri" {
    ./arch-install --target /tmp/x.img --profile desktop --desktop niri --dry-run >/dev/null 2>&1
}

@test "dry-run cachyos(bore 内核)" {
    ./arch-install --target /tmp/x.img --profile server --distro cachyos --cachyos-kernel bore --dry-run >/dev/null 2>&1
}

@test "dry-run 输出含模块顺序(desktop niri)" {
    DRYRUN_OUT=$(./arch-install --target /tmp/x.img --profile desktop --desktop niri --dry-run 2>/dev/null)
    assert_str_contains "$DRYRUN_OUT" "desktop-niri"
}
