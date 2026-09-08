#!/usr/bin/env bats
# tests/devices.bats — section 11: --device 设备预设
# shellcheck disable=SC2314  # bats 中 `! cmd` 唯一最后命令是合法模式,SC2314 误报
load test_helper
setup() {
    setup_repo_root
    ensure_dryrun_config
    mkdir -p devices
    cat >devices/testdev.sh <<'EOF'
DISTRO=cachyos
CPUTYPE=amd
EXTRA_MODULES=gpgpu
MY_HOSTNAME=testdev-host
EOF
}
teardown() {
    cleanup_test_device
    if [[ ${DRYRUN_CLEANUP_CONFIG:-0} == 1 ]]; then
        rm -f config/config.sh
    fi
}

@test "print_plan 显示设备名" {
    device_out=$(./arch-install --target /tmp/x.img --device testdev --dry-run 2>/dev/null)
    assert_str_contains "$device_out" "设备:      testdev"
}

@test "--device 固化 distro 生效" {
    device_out=$(./arch-install --target /tmp/x.img --device testdev --dry-run 2>/dev/null)
    assert_str_contains "$device_out" "发行版:    cachyos"
}

@test "--device 固化 cputype 生效" {
    device_out=$(./arch-install --target /tmp/x.img --device testdev --dry-run 2>/dev/null)
    assert_str_contains "$device_out" "微码:      amd"
}

@test "--device 固化 extra-modules 生效" {
    device_out=$(./arch-install --target /tmp/x.img --device testdev --dry-run 2>/dev/null)
    assert_str_contains "$device_out" "gpgpu"
}

@test "CLI 覆盖设备默认(--distro arch)" {
    cli_over=$(./arch-install --target /tmp/x.img --device testdev --distro arch --dry-run 2>/dev/null)
    assert_str_contains "$cli_over" "发行版:    arch"
}

@test "不存在的设备 die" {
    ! ./arch-install --target /tmp/x.img --device nonexist-dev --dry-run >/dev/null 2>&1
}

@test "非法设备名 die(--device ../etc)" {
    ! ./arch-install --target /tmp/x.img --device ../etc --dry-run >/dev/null 2>&1
}

# ---- 叠加顺序断言 ----
@test "叠加顺序 prescan→config→device→parse" {
    call_order=$(grep -nE '^    (prescan_args|load_config|load_device|parse_args)\b' arch-install \
        | sed 's/^[0-9]*: *//' | cut -d' ' -f1 | paste -sd,)
    assert_str_contains "$call_order" "prescan_args,load_config,load_device,parse_args"
}

@test "--modules 提前 exit 保留在 prescan" {
    grep -A5 '^prescan_args()' arch-install | grep -q -- '--modules'
}

@test "模板 devices/example.sh tracked 例外" {
    [[ -f devices/example.sh ]] && grep -q '!devices/example.sh' .gitignore
}

@test "gitignore 忽略 devices/*.sh" {
    grep -q 'devices/\*.sh' .gitignore
}

@test "usage 含 --device" {
    ./arch-install --help 2>/dev/null | grep -q -- '--device'
}
