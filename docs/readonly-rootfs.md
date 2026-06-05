# Read-Only Root Filesystem (OverlayFS) + Persistent State (Directive 1)

> **Status: implemented as scripts, NOT yet run on the Pi.** `setup-readonly.sh`,
> `toggle-rw.sh`, and `rollback-readonly.sh` exist and pass static checks. They
> have not been executed on the Raspberry Pi. Enabling OverlayFS only takes effect
> after a reboot; none of these scripts reboot for you.

## Goal

The Pi is a pull-the-plug appliance: it must survive sudden power loss without
corrupting the root filesystem. We make the **root read-only** with Raspberry Pi
OS's native OverlayFS, while keeping the small amount of state that genuinely must
survive a reboot:

- **BlueZ pairing data** — `/var/lib/bluetooth`
- **WirePlumber stream/route state** — `~<user>/.local/state/wireplumber`
  (the audio user, e.g. `Panda` — auto-detected, not hardcoded to `pi`)

## Why a loop-mounted ext4 image (not symlinks onto the boot FAT32)

The original idea was to symlink those dirs straight onto the boot partition. The
boot partition (`/boot/firmware`) is **VFAT (FAT32)**, and that breaks BlueZ:

- BlueZ stores pairing data in directories named by MAC address **with colons**
  (e.g. `B8:27:EB:..`). **Colons are illegal in VFAT filenames**, so BlueZ cannot
  even create its adapter directory there.
- VFAT has **no POSIX ownership/permissions**, which BlueZ (`0700 root`) and
  WirePlumber rely on.

So instead we keep **one journaled ext4 image file** on the FAT32 boot partition
(FAT32 is perfectly happy holding a single large opaque file), loop-mount it
read-write, move the two state dirs into it, and symlink the originals back:

```
/boot/firmware/aurabridge_state.ext4        (FAT32 just holds this one 50 MB file)
  └─ loop-mounted at /mnt/persist  (ext4, RW, journaled  ->  power-loss safe)
       ├─ bluetooth/    <-  /var/lib/bluetooth                    (symlink)
       └─ wireplumber/  <-  /home/<user>/.local/state/wireplumber (symlink)
```

ext4's journal keeps that small writable island consistent across power loss,
while the rest of the root is frozen read-only by OverlayFS.

`/etc/fstab` entry (added automatically, with `nofail` so a missing/damaged image
never drops the Pi into an emergency shell):

```
/boot/firmware/aurabridge_state.ext4  /mnt/persist  ext4  loop,defaults,nofail  0  0
```

> **`enable_bootro` is intentionally NOT run.** The boot partition must stay
> writable because the ext4 state image lives on it.

## Setup

Run as the audio user (uses `sudo` internally for root-owned steps):

```bash
./scripts/setup-readonly.sh                 # image + mount + migrate, then enable overlay (prompts)
./scripts/setup-readonly.sh --prepare-only  # everything EXCEPT enabling overlay
./scripts/setup-readonly.sh --status        # report current state; change nothing
sudo reboot                                  # required to activate the read-only root
```

It is idempotent: re-running re-asserts state and never double-moves data. Tunables
via env: `PERSIST_MNT`, `STATE_IMAGE_MB`, `BOOT_DIR`, `TARGET_USER`, `ASSUME_YES=1`.

## Updating the system later (temporary writable root)

OverlayFS discards root writes on reboot, so to install updates you lift the
overlay, reboot writable, update, then re-freeze. The persistence image/symlinks
are left untouched throughout:

```bash
./scripts/toggle-rw.sh rw  && sudo reboot     # boot with a writable root
sudo apt-get update && sudo apt-get full-upgrade
./scripts/toggle-rw.sh ro  && sudo reboot     # re-freeze read-only
./scripts/toggle-rw.sh status                 # check which state you're in
```

## Full teardown / rollback

Two phases around one reboot (because disabling the overlay only applies on
reboot):

```bash
# Phase 1 — root still read-only:
./scripts/rollback-readonly.sh --disable-overlay
sudo reboot

# Phase 2 — after reboot, root writable:
./scripts/rollback-readonly.sh --restore
```

`--restore` removes the symlinks, copies the state back to the original
locations, drops the `/etc/fstab` entry, unmounts `/mnt/persist`, and deletes the
ext4 image — leaving a plain read-write root. `--status` (default) reports what
remains and which phase to run next. Every step is idempotent.

## Boot ordering note

`/mnt/persist` is a normal `local-fs` mount, so it comes up before
`bluetooth.service` and well before the user WirePlumber session — the symlinked
state is in place by the time anything reads it. systemd also adds an implicit
`RequiresMountsFor` on the backing file, so the loop mount is ordered after
`/boot/firmware` is mounted.

## Relationship to the rest of the project

This is orthogonal to audio routing and volume safety. It does **not** change the
PipeWire graph, does not unblock DLNA, and does not alter the Safe Sink or the
Bluetooth policy — it only makes the root resilient and keeps pairing/route state
across reboots and power cuts.
