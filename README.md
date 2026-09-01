# arch-install

Personal Arch / CachyOS / Arch Linux ARM (aarch64) installer. Pure bash, modular. Built for my own machines; published as reference — feel free to read and adapt.

Refactored from a single-file script: everything belonging to one feature (package install, config, systemd enable) now lives in one module file; all personal data (username, keys, LAN addresses, backup target) moved into gitignored `config/`, so this repo is safe to publish.

## Features

- **Three distros**: Arch, CachyOS (selectable kernel variants and v3/v4/znver4 repo optimization; keyring/mirrorlist versions queried live from the CDN, or bring your own mirrorlist via `MY_CACHYOS_MIRRORLIST`), and Arch Linux ARM (`--distro alarm`, aarch64 images cross-built from an x86_64 host; see the dedicated section below)
- **Cross-CPU builds**: `--cputype amd|intel` when building for a different machine (e.g. build for an AMD box from an Intel one)
- **Two targets**: raw disk image (auto losetup) or physical drive (auto-detected, full wipe, interactive confirm + `--force` + in-use pre-check)
- **Modular**: one `modules/*.sh` per feature; modules declare requires/conflicts/before; the resolver computes the closure and topo-sorts
- **Profiles**: `server` / `desktop` (niri or KDE); VPS = server + `--skip-modules hardware`; `--extra-modules` / `--skip-modules` for arbitrary tweaks
- **Device presets**: `--device NAME` loads `devices/NAME.sh` (gitignored; `devices/example.sh` is the tracked template) to pin per-device CLI defaults (`--distro`, `--cputype`, kernel variant, `--extra-modules`, …) and `MY_*` overrides. Precedence: built-in defaults → `config.sh` → device file → explicit CLI flags. `TARGET`/`--force`/`--dry-run` cannot be pinned; `--profile` is passed explicitly on every run by convention
- **Mirrorlist, four sources**: copy from host / upstream default / reflector-generated / config file. Filenames always match the official packages (`mirrorlist`, `archcn-mirrorlist`, `cachyos-mirrorlist`) so you can switch back to package-managed lists anytime; in `original` mode the packages themselves are installed
- **Root auto-grow at first boot**: systemd-repart expands both the GPT partition and the btrfs filesystem
- **btrfs NOCOW for hot-write dirs**: on btrfs roots, `chattr +C` is applied at install time to `/var/log/journal`, plus `/var/log/audit` (auditd module) and `/var/lib/libvirt/images` (virt module) — skips copy-on-write for append-heavy logs and VM images, avoiding fragmentation
- **Memory options**: default `mem-zswap` (tmpfiles.d config + btrfs NOCOW swapfile backing, `MY_SWAP_SIZE` default 4G; `0` falls back to zram); `mem-zram` (zram-generator) as alternative; remove the module for no swap at all — the two are mutually exclusive
- **Sparse images**: raw images are sparse files (host disk usage = actual data only) with fstrim on cleanup to punch freed blocks back
- **Secrets strategy**: copy (images) / firstboot (physical) / keyfile (git-crypt symmetric key) / none
- **Privacy-safe**: personal data lives only in `config/config.sh` and `config/hooks.sh` (gitignored); templates are tracked

## Usage

```bash
cp config/config.example.sh config/config.sh   # set MY_USERNAME etc.
sudo ./arch-install --target system.img --size 15G --profile desktop --desktop niri
sudo ./arch-install --target /dev/sda --profile server --force
sudo ./arch-install --target vps.img --profile server --skip-modules hardware
sudo ./arch-install --target cachy.img --distro cachyos --cachyos-kernel bore
sudo ./arch-install --device hx370 --target /dev/nvme0n1 --profile desktop   # device preset: pinned flags from devices/hx370.sh
./arch-install --target x.img --profile desktop --dry-run   # preview, no root needed
./arch-install --modules   # list all modules, deps and ordering constraints
```

Full options: `./arch-install --help`.

Boot-test an image:

```bash
qemu-system-x86_64 -m 4G -bios /usr/share/ovmf/x64/OVMF.4m.fd -drive file=system.img,format=raw
```

aarch64 (`--distro alarm`) images cannot be boot-tested with `qemu-system-x86_64`; they need real hardware or `qemu-system-aarch64` (this installer provides no such emulation path).

## Arch Linux ARM (aarch64)

`--distro alarm` cross-builds an Arch Linux ARM image from an x86_64 host. Target: RK3588 boards (Orange Pi 5 Plus) running edk2-rk3588 UEFI firmware; image build and on-device boot verification is a follow-up task.

Host requirements:

- `qemu-user-static` + `qemu-user-static-binfmt`, with the `qemu-aarch64` binfmt rule registered **with the F (fix_binary) flag**, otherwise aarch64 binaries cannot run inside the chroot. The host preflight dies before touching the disk if the rule is missing, disabled, or lacks F.
- The alarm build key (`68B3537F39A313B3E574D06777193F152BDBE6A6`) is fetched and lsigned into the **host** pacman keyring before pacstrap. This is a persistent host-side modification, done once.
- Expect roughly double build time: every chroot binary executes under qemu-user, and gpg operations (`pacman-key --init`) are especially slow. This is normal.

`MY_ALARM_MIRROR` picks the mirror; the value must contain `$arch`/`$repo` placeholders (e.g. `https://mirrors.ustc.edu.cn/archlinuxarm/$arch/$repo`). Empty means the GeoDNS default `mirror.archlinuxarm.org`.

Example with the OPi5+ device preset (gitignored `devices/opi5plus.sh`; template in `devices/example.sh`):

```bash
sudo ./arch-install --device opi5plus --target opi5plus.img --profile server
dd if=opi5plus.img of=/dev/sdX bs=4M status=progress conv=fsync   # write to SD / eMMC / NVMe
# First boot: systemd-repart + systemd-growfs expand the root partition and btrfs to the full disk
```

> **Warning**: the boot media (SD / eMMC / NVMe) must not contain U-Boot remnants, otherwise the edk2-rk3588 firmware may prefer the leftover U-Boot and break the boot chain. The SPI flash is the exception: it must run edk2-rk3588.

Current limitations:

- Only the `server` profile is validated on alarm; the `desktop` profile is untested.
- alarm has no `efifs` package, so XBOOTLDR (`/boot`) is FAT32 instead of ext4.
- Boot entries skip `add_efi_memmap` (x86-only option).
- Kernel is `linux-aarch64`; mkinitcpio `autodetect` is temporarily removed during install (under qemu-user it reads the x86_64 host's /sys) and restored in post-install.

## Layout

```
arch-install          entry point: arg parsing, orchestration, cleanup trap
lib/                  common (log/dep-check) disk (partition/mount/bootctl) chroot (helpers) modules (resolver)
distro/               arch.sh / cachyos.sh / alarm.sh (distro differences: repos, keyring, kernel)
modules/              feature modules (interface below)
profiles/             server.conf / desktop.conf (MODULES presets)
config/               config.example.sh + hooks.example.sh (tracked templates);
                      config.sh + hooks.sh (gitignored, your personal config)
devices/              example.sh (tracked template); NAME.sh per-device presets
                      (gitignored, loaded via `--device NAME`)
tests/run.sh          pure-bash self tests (syntax, module contract, conventions, resolver unit tests, dry-run)
docs/plans/           design doc and execution plan (Chinese)
```

## Module overview

```
core:      base pacman growfs ssh
system:    security filesystems chrony sysctl firewall debug monitoring hardware backup
network:   network-networkd (server) / network-nm (desktop)
tools:     cli-tools dev-tools docker virt
desktop:   audio fonts ime bluetooth desktop-niri desktop-kde gui-apps gaming
gpu (opt): gpu-amd gpu-nvidia gpu-intel gpgpu (OpenCL/ROCm/CUDA, `MY_GPGPU`)
storage (opt): zfs (OpenZFS data pools, `--extra-modules zfs`; root stays btrfs)
```

The `[archlinuxcn]` repo is always configured by the `pacman` module — packages like `rime-ice-git` and `an-anime-game-launcher-bwrap` only exist there. KDE-only apps (dolphin, kate, tokodon, …) live in `desktop-kde`; `gui-apps` holds DE-agnostic apps only. `[multilib]` is enabled unconditionally by `distro_setup_repos` (both Arch and CachyOS), so wine/steam and other 32-bit deps work even when `--skip-modules pacman` is used. Under `--distro alarm` (aarch64): `hardware` skips turbostat (x86-only), `dev-tools` skips opencode/shellcheck/biome and `cli-tools` skips hwinfo/vi (none exist in the alarm or archlinuxcn aarch64 repos — verified against the repo databases), and `yay` comes from the archlinuxcn aarch64 repo.

## Module interface

```bash
mod_requires()  { echo audio fonts; }        # dependencies: auto-included, ordered first
mod_conflicts() { echo desktop-kde; }        # conflicts: hard error if combined
mod_before()    { echo desktop-niri; }       # ordering constraint (comment why!)
mod_install()   { pacman_install xxx; chroot_write_file ...; chroot_enable ...; }
```

Conventions:

- **No hardcoded personal data** in modules; read `MY_*` vars only, skip when empty (enforced by `tests/run.sh`)
- Install + config + service-enable for one feature must stay in the same file
- `pacman_install` runs `pacman -Sc` after every install (image space protection)
- Comment every install-order-sensitive spot (pacman picks `a` alphabetically for `a or b` deps)

Adding a feature: write `modules/foo.sh` → add to a profile or use `--extra-modules` → sync AGENTS.md / README / CHANGELOG.

## Docs

- Design: `docs/plans/2026-07-28-arch-install-design.md` (Chinese)
- Plan: `docs/plans/2026-07-28-arch-install-plan.md` (Chinese)
- Conventions & TODO: `AGENTS.md` (Chinese)

[中文 README](README.zh-CN.md)
