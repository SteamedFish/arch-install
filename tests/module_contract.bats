#!/usr/bin/env bats
# tests/module_contract.bats — section 2: 每个模块必须有 mod_install 且 requires/conflicts/before
# 引用的模块文件存在(不存在则架构错)
# dep 检查用单源 source 模块取函数输出,每个 dep 单独 @test 保证精确定位
load test_helper
setup() { setup_repo_root; }

# helper: 模块定义了函数?(grep 函数定义行)
# assert_module_defined_fn <module> <fn-name>
assert_module_defined_fn() {
    grep -qE "^$2\(\)" "$1" || {
        echo "missing $2() in $1" >&2
        return 1
    }
}

# helper: 取得 mod_<fn> 的输出(sourcing 后调用)
# module_get_deps <module> <fn-name>
module_get_deps() {
    bash -c "source '$1'; $2" 2>/dev/null
}

# helper: 验证模块的 mod_<fn> 引用的所有模块文件都存在
# assert_deps_exist <module> <fn-name>
assert_deps_exist() {
    local deps
    deps=$(module_get_deps "$1" "$2") || true
    [[ -z $deps ]] && return 0   # 未声明依赖,跳过
    for d in $deps; do
        [[ -f "modules/$d.sh" ]] || { echo "$1: $2 引用不存在的 $d" >&2; return 1; }
    done
}

# ---- 每个模块必须有 mod_install() ----
@test "auditd: 定义 mod_install" {                assert_module_defined_fn modules/auditd.sh          mod_install; }
@test "audio: 定义 mod_install" {                 assert_module_defined_fn modules/audio.sh           mod_install; }
@test "backup: 定义 mod_install" {                assert_module_defined_fn modules/backup.sh          mod_install; }
@test "base: 定义 mod_install" {                  assert_module_defined_fn modules/base.sh            mod_install; }
@test "bluetooth: 定义 mod_install" {             assert_module_defined_fn modules/bluetooth.sh       mod_install; }
@test "chrony: 定义 mod_install" {                assert_module_defined_fn modules/chrony.sh          mod_install; }
@test "cli-tools: 定义 mod_install" {             assert_module_defined_fn modules/cli-tools.sh       mod_install; }
@test "debug: 定义 mod_install" {                 assert_module_defined_fn modules/debug.sh           mod_install; }
@test "desktop-kde: 定义 mod_install" {           assert_module_defined_fn modules/desktop-kde.sh     mod_install; }
@test "desktop-niri: 定义 mod_install" {          assert_module_defined_fn modules/desktop-niri.sh    mod_install; }
@test "dev-tools: 定义 mod_install" {             assert_module_defined_fn modules/dev-tools.sh       mod_install; }
@test "docker: 定义 mod_install" {                assert_module_defined_fn modules/docker.sh          mod_install; }
@test "filesystems: 定义 mod_install" {           assert_module_defined_fn modules/filesystems.sh     mod_install; }
@test "firewall: 定义 mod_install" {              assert_module_defined_fn modules/firewall.sh        mod_install; }
@test "fonts: 定义 mod_install" {                 assert_module_defined_fn modules/fonts.sh           mod_install; }
@test "gaming: 定义 mod_install" {                assert_module_defined_fn modules/gaming.sh          mod_install; }
@test "gpgpu: 定义 mod_install" {                 assert_module_defined_fn modules/gpgpu.sh           mod_install; }
@test "gpu-amd: 定义 mod_install" {               assert_module_defined_fn modules/gpu-amd.sh         mod_install; }
@test "gpu-intel: 定义 mod_install" {             assert_module_defined_fn modules/gpu-intel.sh       mod_install; }
@test "gpu-nvidia: 定义 mod_install" {            assert_module_defined_fn modules/gpu-nvidia.sh      mod_install; }
@test "growfs: 定义 mod_install" {                assert_module_defined_fn modules/growfs.sh          mod_install; }
@test "gui-apps: 定义 mod_install" {              assert_module_defined_fn modules/gui-apps.sh        mod_install; }
@test "hardware: 定义 mod_install" {              assert_module_defined_fn modules/hardware.sh        mod_install; }
@test "ime: 定义 mod_install" {                   assert_module_defined_fn modules/ime.sh             mod_install; }
@test "mem-zram: 定义 mod_install" {              assert_module_defined_fn modules/mem-zram.sh        mod_install; }
@test "mem-zswap: 定义 mod_install" {             assert_module_defined_fn modules/mem-zswap.sh       mod_install; }
@test "monitoring: 定义 mod_install" {            assert_module_defined_fn modules/monitoring.sh      mod_install; }
@test "network-networkd: 定义 mod_install" {     assert_module_defined_fn modules/network-networkd.sh mod_install; }
@test "network-nm: 定义 mod_install" {            assert_module_defined_fn modules/network-nm.sh      mod_install; }
@test "pacman: 定义 mod_install" {                assert_module_defined_fn modules/pacman.sh          mod_install; }
@test "security: 定义 mod_install" {              assert_module_defined_fn modules/security.sh        mod_install; }
@test "ssh: 定义 mod_install" {                   assert_module_defined_fn modules/ssh.sh             mod_install; }
@test "sysctl: 定义 mod_install" {                assert_module_defined_fn modules/sysctl.sh          mod_install; }
@test "virt: 定义 mod_install" {                  assert_module_defined_fn modules/virt.sh            mod_install; }
@test "zfs: 定义 mod_install" {                   assert_module_defined_fn modules/zfs.sh             mod_install; }

# ---- 每个模块的 mod_requires 引用的模块都存在 ----
@test "auditd.mod_requires 引用都存在" {          assert_deps_exist modules/auditd.sh          mod_requires; }
@test "audio.mod_requires 引用都存在" {           assert_deps_exist modules/audio.sh           mod_requires; }
@test "backup.mod_requires 引用都存在" {          assert_deps_exist modules/backup.sh          mod_requires; }
@test "base.mod_requires 引用都存在" {            assert_deps_exist modules/base.sh            mod_requires; }
@test "bluetooth.mod_requires 引用都存在" {       assert_deps_exist modules/bluetooth.sh       mod_requires; }
@test "chrony.mod_requires 引用都存在" {          assert_deps_exist modules/chrony.sh          mod_requires; }
@test "cli-tools.mod_requires 引用都存在" {       assert_deps_exist modules/cli-tools.sh       mod_requires; }
@test "debug.mod_requires 引用都存在" {           assert_deps_exist modules/debug.sh           mod_requires; }
@test "desktop-kde.mod_requires 引用都存在" {     assert_deps_exist modules/desktop-kde.sh     mod_requires; }
@test "desktop-niri.mod_requires 引用都存在" {    assert_deps_exist modules/desktop-niri.sh    mod_requires; }
@test "dev-tools.mod_requires 引用都存在" {       assert_deps_exist modules/dev-tools.sh       mod_requires; }
@test "docker.mod_requires 引用都存在" {          assert_deps_exist modules/docker.sh          mod_requires; }
@test "filesystems.mod_requires 引用都存在" {     assert_deps_exist modules/filesystems.sh     mod_requires; }
@test "firewall.mod_requires 引用都存在" {        assert_deps_exist modules/firewall.sh        mod_requires; }
@test "fonts.mod_requires 引用都存在" {           assert_deps_exist modules/fonts.sh           mod_requires; }
@test "gaming.mod_requires 引用都存在" {          assert_deps_exist modules/gaming.sh          mod_requires; }
@test "gpgpu.mod_requires 引用都存在" {           assert_deps_exist modules/gpgpu.sh           mod_requires; }
@test "gpu-amd.mod_requires 引用都存在" {         assert_deps_exist modules/gpu-amd.sh         mod_requires; }
@test "gpu-intel.mod_requires 引用都存在" {       assert_deps_exist modules/gpu-intel.sh       mod_requires; }
@test "gpu-nvidia.mod_requires 引用都存在" {      assert_deps_exist modules/gpu-nvidia.sh      mod_requires; }
@test "growfs.mod_requires 引用都存在" {          assert_deps_exist modules/growfs.sh          mod_requires; }
@test "gui-apps.mod_requires 引用都存在" {        assert_deps_exist modules/gui-apps.sh        mod_requires; }
@test "hardware.mod_requires 引用都存在" {        assert_deps_exist modules/hardware.sh        mod_requires; }
@test "ime.mod_requires 引用都存在" {             assert_deps_exist modules/ime.sh             mod_requires; }
@test "mem-zram.mod_requires 引用都存在" {        assert_deps_exist modules/mem-zram.sh        mod_requires; }
@test "mem-zswap.mod_requires 引用都存在" {       assert_deps_exist modules/mem-zswap.sh       mod_requires; }
@test "monitoring.mod_requires 引用都存在" {      assert_deps_exist modules/monitoring.sh      mod_requires; }
@test "network-networkd.mod_requires 引用都存在" { assert_deps_exist modules/network-networkd.sh mod_requires; }
@test "network-nm.mod_requires 引用都存在" {      assert_deps_exist modules/network-nm.sh      mod_requires; }
@test "pacman.mod_requires 引用都存在" {          assert_deps_exist modules/pacman.sh          mod_requires; }
@test "security.mod_requires 引用都存在" {        assert_deps_exist modules/security.sh        mod_requires; }
@test "ssh.mod_requires 引用都存在" {             assert_deps_exist modules/ssh.sh             mod_requires; }
@test "sysctl.mod_requires 引用都存在" {          assert_deps_exist modules/sysctl.sh          mod_requires; }
@test "virt.mod_requires 引用都存在" {            assert_deps_exist modules/virt.sh            mod_requires; }
@test "zfs.mod_requires 引用都存在" {             assert_deps_exist modules/zfs.sh             mod_requires; }

# ---- 每个模块的 mod_conflicts 引用的模块都存在 ----
@test "auditd.mod_conflicts 引用都存在" {          assert_deps_exist modules/auditd.sh          mod_conflicts; }
@test "audio.mod_conflicts 引用都存在" {           assert_deps_exist modules/audio.sh           mod_conflicts; }
@test "backup.mod_conflicts 引用都存在" {          assert_deps_exist modules/backup.sh          mod_conflicts; }
@test "base.mod_conflicts 引用都存在" {            assert_deps_exist modules/base.sh            mod_conflicts; }
@test "bluetooth.mod_conflicts 引用都存在" {       assert_deps_exist modules/bluetooth.sh       mod_conflicts; }
@test "chrony.mod_conflicts 引用都存在" {          assert_deps_exist modules/chrony.sh          mod_conflicts; }
@test "cli-tools.mod_conflicts 引用都存在" {       assert_deps_exist modules/cli-tools.sh       mod_conflicts; }
@test "debug.mod_conflicts 引用都存在" {           assert_deps_exist modules/debug.sh           mod_conflicts; }
@test "desktop-kde.mod_conflicts 引用都存在" {     assert_deps_exist modules/desktop-kde.sh     mod_conflicts; }
@test "desktop-niri.mod_conflicts 引用都存在" {    assert_deps_exist modules/desktop-niri.sh    mod_conflicts; }
@test "dev-tools.mod_conflicts 引用都存在" {       assert_deps_exist modules/dev-tools.sh       mod_conflicts; }
@test "docker.mod_conflicts 引用都存在" {          assert_deps_exist modules/docker.sh          mod_conflicts; }
@test "filesystems.mod_conflicts 引用都存在" {     assert_deps_exist modules/filesystems.sh     mod_conflicts; }
@test "firewall.mod_conflicts 引用都存在" {        assert_deps_exist modules/firewall.sh        mod_conflicts; }
@test "fonts.mod_conflicts 引用都存在" {           assert_deps_exist modules/fonts.sh           mod_conflicts; }
@test "gaming.mod_conflicts 引用都存在" {          assert_deps_exist modules/gaming.sh          mod_conflicts; }
@test "gpgpu.mod_conflicts 引用都存在" {           assert_deps_exist modules/gpgpu.sh           mod_conflicts; }
@test "gpu-amd.mod_conflicts 引用都存在" {         assert_deps_exist modules/gpu-amd.sh         mod_conflicts; }
@test "gpu-intel.mod_conflicts 引用都存在" {       assert_deps_exist modules/gpu-intel.sh       mod_conflicts; }
@test "gpu-nvidia.mod_conflicts 引用都存在" {      assert_deps_exist modules/gpu-nvidia.sh      mod_conflicts; }
@test "growfs.mod_conflicts 引用都存在" {          assert_deps_exist modules/growfs.sh          mod_conflicts; }
@test "gui-apps.mod_conflicts 引用都存在" {        assert_deps_exist modules/gui-apps.sh        mod_conflicts; }
@test "hardware.mod_conflicts 引用都存在" {        assert_deps_exist modules/hardware.sh        mod_conflicts; }
@test "ime.mod_conflicts 引用都存在" {             assert_deps_exist modules/ime.sh             mod_conflicts; }
@test "mem-zram.mod_conflicts 引用都存在" {        assert_deps_exist modules/mem-zram.sh        mod_conflicts; }
@test "mem-zswap.mod_conflicts 引用都存在" {       assert_deps_exist modules/mem-zswap.sh       mod_conflicts; }
@test "monitoring.mod_conflicts 引用都存在" {      assert_deps_exist modules/monitoring.sh      mod_conflicts; }
@test "network-networkd.mod_conflicts 引用都存在" { assert_deps_exist modules/network-networkd.sh mod_conflicts; }
@test "network-nm.mod_conflicts 引用都存在" {      assert_deps_exist modules/network-nm.sh      mod_conflicts; }
@test "pacman.mod_conflicts 引用都存在" {          assert_deps_exist modules/pacman.sh          mod_conflicts; }
@test "security.mod_conflicts 引用都存在" {        assert_deps_exist modules/security.sh        mod_conflicts; }
@test "ssh.mod_conflicts 引用都存在" {             assert_deps_exist modules/ssh.sh             mod_conflicts; }
@test "sysctl.mod_conflicts 引用都存在" {          assert_deps_exist modules/sysctl.sh          mod_conflicts; }
@test "virt.mod_conflicts 引用都存在" {            assert_deps_exist modules/virt.sh            mod_conflicts; }
@test "zfs.mod_conflicts 引用都存在" {             assert_deps_exist modules/zfs.sh             mod_conflicts; }

# ---- 每个模块的 mod_before 引用的模块都存在 ----
@test "auditd.mod_before 引用都存在" {          assert_deps_exist modules/auditd.sh          mod_before; }
@test "audio.mod_before 引用都存在" {           assert_deps_exist modules/audio.sh           mod_before; }
@test "backup.mod_before 引用都存在" {          assert_deps_exist modules/backup.sh          mod_before; }
@test "base.mod_before 引用都存在" {            assert_deps_exist modules/base.sh            mod_before; }
@test "bluetooth.mod_before 引用都存在" {       assert_deps_exist modules/bluetooth.sh       mod_before; }
@test "chrony.mod_before 引用都存在" {          assert_deps_exist modules/chrony.sh          mod_before; }
@test "cli-tools.mod_before 引用都存在" {       assert_deps_exist modules/cli-tools.sh       mod_before; }
@test "debug.mod_before 引用都存在" {           assert_deps_exist modules/debug.sh           mod_before; }
@test "desktop-kde.mod_before 引用都存在" {     assert_deps_exist modules/desktop-kde.sh     mod_before; }
@test "desktop-niri.mod_before 引用都存在" {    assert_deps_exist modules/desktop-niri.sh    mod_before; }
@test "dev-tools.mod_before 引用都存在" {       assert_deps_exist modules/dev-tools.sh       mod_before; }
@test "docker.mod_before 引用都存在" {          assert_deps_exist modules/docker.sh          mod_before; }
@test "filesystems.mod_before 引用都存在" {     assert_deps_exist modules/filesystems.sh     mod_before; }
@test "firewall.mod_before 引用都存在" {        assert_deps_exist modules/firewall.sh        mod_before; }
@test "fonts.mod_before 引用都存在" {           assert_deps_exist modules/fonts.sh           mod_before; }
@test "gaming.mod_before 引用都存在" {          assert_deps_exist modules/gaming.sh          mod_before; }
@test "gpgpu.mod_before 引用都存在" {           assert_deps_exist modules/gpgpu.sh           mod_before; }
@test "gpu-amd.mod_before 引用都存在" {         assert_deps_exist modules/gpu-amd.sh         mod_before; }
@test "gpu-intel.mod_before 引用都存在" {       assert_deps_exist modules/gpu-intel.sh       mod_before; }
@test "gpu-nvidia.mod_before 引用都存在" {      assert_deps_exist modules/gpu-nvidia.sh      mod_before; }
@test "growfs.mod_before 引用都存在" {          assert_deps_exist modules/growfs.sh          mod_before; }
@test "gui-apps.mod_before 引用都存在" {        assert_deps_exist modules/gui-apps.sh        mod_before; }
@test "hardware.mod_before 引用都存在" {        assert_deps_exist modules/hardware.sh        mod_before; }
@test "ime.mod_before 引用都存在" {             assert_deps_exist modules/ime.sh             mod_before; }
@test "mem-zram.mod_before 引用都存在" {        assert_deps_exist modules/mem-zram.sh        mod_before; }
@test "mem-zswap.mod_before 引用都存在" {       assert_deps_exist modules/mem-zswap.sh       mod_before; }
@test "monitoring.mod_before 引用都存在" {      assert_deps_exist modules/monitoring.sh      mod_before; }
@test "network-networkd.mod_before 引用都存在" { assert_deps_exist modules/network-networkd.sh mod_before; }
@test "network-nm.mod_before 引用都存在" {      assert_deps_exist modules/network-nm.sh      mod_before; }
@test "pacman.mod_before 引用都存在" {          assert_deps_exist modules/pacman.sh          mod_before; }
@test "security.mod_before 引用都存在" {        assert_deps_exist modules/security.sh        mod_before; }
@test "ssh.mod_before 引用都存在" {             assert_deps_exist modules/ssh.sh             mod_before; }
@test "sysctl.mod_before 引用都存在" {          assert_deps_exist modules/sysctl.sh          mod_before; }
@test "virt.mod_before 引用都存在" {            assert_deps_exist modules/virt.sh            mod_before; }
@test "zfs.mod_before 引用都存在" {             assert_deps_exist modules/zfs.sh             mod_before; }
