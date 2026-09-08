#!/usr/bin/env bats
# tests/syntax.bats — section 1: 所有 bash 文件独立 @test 逐一过 bash -n
load test_helper
setup() { setup_repo_root; }

# ---- arch-install 主入口 ----
@test "bash -n arch-install" {
    assert_bash_syntax arch-install
}

# ---- lib/*.sh ----
@test "bash -n lib/common.sh" {       assert_bash_syntax lib/common.sh; }
@test "bash -n lib/disk.sh" {         assert_bash_syntax lib/disk.sh; }
@test "bash -n lib/chroot.sh" {       assert_bash_syntax lib/chroot.sh; }
@test "bash -n lib/modules.sh" {      assert_bash_syntax lib/modules.sh; }

# ---- distro/*.sh ----
@test "bash -n distro/arch.sh" {      assert_bash_syntax distro/arch.sh; }
@test "bash -n distro/cachyos.sh" {   assert_bash_syntax distro/cachyos.sh; }

# ---- modules/*.sh ----
@test "bash -n modules/auditd.sh" {          assert_bash_syntax modules/auditd.sh; }
@test "bash -n modules/audio.sh" {           assert_bash_syntax modules/audio.sh; }
@test "bash -n modules/backup.sh" {          assert_bash_syntax modules/backup.sh; }
@test "bash -n modules/base.sh" {            assert_bash_syntax modules/base.sh; }
@test "bash -n modules/bluetooth.sh" {       assert_bash_syntax modules/bluetooth.sh; }
@test "bash -n modules/chrony.sh" {          assert_bash_syntax modules/chrony.sh; }
@test "bash -n modules/cli-tools.sh" {       assert_bash_syntax modules/cli-tools.sh; }
@test "bash -n modules/debug.sh" {           assert_bash_syntax modules/debug.sh; }
@test "bash -n modules/desktop-kde.sh" {     assert_bash_syntax modules/desktop-kde.sh; }
@test "bash -n modules/desktop-niri.sh" {    assert_bash_syntax modules/desktop-niri.sh; }
@test "bash -n modules/dev-tools.sh" {       assert_bash_syntax modules/dev-tools.sh; }
@test "bash -n modules/docker.sh" {          assert_bash_syntax modules/docker.sh; }
@test "bash -n modules/filesystems.sh" {     assert_bash_syntax modules/filesystems.sh; }
@test "bash -n modules/firewall.sh" {        assert_bash_syntax modules/firewall.sh; }
@test "bash -n modules/fonts.sh" {           assert_bash_syntax modules/fonts.sh; }
@test "bash -n modules/gaming.sh" {          assert_bash_syntax modules/gaming.sh; }
@test "bash -n modules/gpgpu.sh" {           assert_bash_syntax modules/gpgpu.sh; }
@test "bash -n modules/gpu-amd.sh" {         assert_bash_syntax modules/gpu-amd.sh; }
@test "bash -n modules/gpu-intel.sh" {       assert_bash_syntax modules/gpu-intel.sh; }
@test "bash -n modules/gpu-nvidia.sh" {      assert_bash_syntax modules/gpu-nvidia.sh; }
@test "bash -n modules/growfs.sh" {          assert_bash_syntax modules/growfs.sh; }
@test "bash -n modules/gui-apps.sh" {        assert_bash_syntax modules/gui-apps.sh; }
@test "bash -n modules/hardware.sh" {        assert_bash_syntax modules/hardware.sh; }
@test "bash -n modules/ime.sh" {             assert_bash_syntax modules/ime.sh; }
@test "bash -n modules/mem-zram.sh" {        assert_bash_syntax modules/mem-zram.sh; }
@test "bash -n modules/mem-zswap.sh" {       assert_bash_syntax modules/mem-zswap.sh; }
@test "bash -n modules/monitoring.sh" {      assert_bash_syntax modules/monitoring.sh; }
@test "bash -n modules/network-networkd.sh" { assert_bash_syntax modules/network-networkd.sh; }
@test "bash -n modules/network-nm.sh" {     assert_bash_syntax modules/network-nm.sh; }
@test "bash -n modules/pacman.sh" {          assert_bash_syntax modules/pacman.sh; }
@test "bash -n modules/security.sh" {        assert_bash_syntax modules/security.sh; }
@test "bash -n modules/ssh.sh" {             assert_bash_syntax modules/ssh.sh; }
@test "bash -n modules/sysctl.sh" {          assert_bash_syntax modules/sysctl.sh; }
@test "bash -n modules/virt.sh" {            assert_bash_syntax modules/virt.sh; }
@test "bash -n modules/zfs.sh" {             assert_bash_syntax modules/zfs.sh; }

# ---- profiles/*.conf ----
@test "bash -n profiles/desktop.conf" {      assert_bash_syntax profiles/desktop.conf; }
@test "bash -n profiles/server.conf" {       assert_bash_syntax profiles/server.conf; }

# ---- config/*.example.sh(模板)----
@test "bash -n config/config.example.sh" {   assert_bash_syntax config/config.example.sh; }
@test "bash -n config/hooks.example.sh" {    assert_bash_syntax config/hooks.example.sh; }
