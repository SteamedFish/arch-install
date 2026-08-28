# arch-install

Personal Arch / CachyOS installer. Pure bash, modular. Built for my own machines; published as reference — feel free to read and adapt.

Refactored from a single-file script: everything belonging to one feature (package install, config, systemd enable) now lives in one module file; all personal data (username, keys, LAN addresses, backup target) moved into gitignored `config/`, so this repo is safe to publish.

## Features

- **Two distros**: Arch and CachyOS (selectable kernel variants and v3/v4/znver4 repo optimization; keyring/mirrorlist versions queried live from the CDN, or bring your own mirrorlist via `MY_CACHYOS_MIRRORLIST`)
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

## Layout

```
arch-install          entry point: arg parsing, orchestration, cleanup trap
lib/                  common (log/dep-check) disk (partition/mount/bootctl) chroot (helpers) modules (resolver)
distro/               arch.sh / cachyos.sh (distro differences: repos, keyring, kernel)
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

The `[archlinuxcn]` repo is always configured by the `pacman` module — packages like `rime-ice-git` and `an-anime-game-launcher-bwrap` only exist there. KDE-only apps (dolphin, kate, tokodon, …) live in `desktop-kde`; `gui-apps` holds DE-agnostic apps only. `[multilib]` is enabled unconditionally by `distro_setup_repos` (both Arch and CachyOS), so wine/steam and other 32-bit deps work even when `--skip-modules pacman` is used.

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
