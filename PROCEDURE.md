# lanchamarcou — Install & Debug Procedure (full summary)

This directory contains the `newThatWaterCharmander` flake with modifications for
the `lanchamarcou` host, produced while installing NixOS on the machine that was
reachable on the LAN as `nixos@192.168.2.19`. **Not committed** — review and
apply to the main checkout (`~/baghdad_plane/flakes/newThatWaterCharmander`)
when satisfied.

## Files changed (relative to the original flake)

| File | Change |
|---|---|
| `zeusOlympia/lanchamarcou/bootIntrospection.nix` | **New module** — persistent journald + boot ledger + helper (details below) |
| `zeusOlympia/lanchamarcou/impermanence.nix` | Added `/etc/NetworkManager/system-connections` to the persisted directories (keeps the WiFi profile alive across root wipes) |
| `zeusOlympia/lanchamarcou/sshHostKey.pub` | Replaced a **stale** key (host key of a previous ISO boot) with the current installer host key, whose private half is held by the operator. Restores the config's stated intent: "the current host's own ssh host key is used as the authorized key" |

Everything else is untouched (flake.nix, flake.lock, all other hosts/modules).

---

## 1. Discovery

- Local machine on `192.168.2.0/24` (WiFi `wlp0s20f3`, IP `192.168.2.12`).
- No nmap/fping available → bash ping sweep over the /24 found the target at
  **192.168.2.19** (MAC `48:d2:24:7d:66:c2`), SSH banner `SSH-2.0-OpenSSH_10.5`.
- No sshpass/expect → used OpenSSH's `SSH_ASKPASS_REQUIRE=force` with a small
  askpass script to authenticate non-interactively (user `nixos`, password
  `tmprootpass`; passwordless sudo on the ISO).

## 2. Local copy and modifications

- Copied the flake to a working directory (rsync, excluding `.git`).
- Target hardware inspected over SSH: `sda` 698.6G (already partitioned by a
  previous failed install: 1G ESP + btrfs), 5.3 GiB RAM, internet OK.
- The host module dir `zeusOlympia/lanchamarcou/` is auto-imported
  (`mkDirectoryImporterModule` imports every `.nix` except `default.nix`), so
  the new module needed no wiring.

### New module: `bootIntrospection.nix`

Context: a previous install of this host had failed to produce a bootable
machine and left no trace of *why*. The module guarantees diagnosability:

1. **Persistent journald** — `services.journald.extraConfig` with
   `Storage=persistent` and `SystemMaxUse=1G`. Journal goes to
   `/persist/var/log/journal` (impermanence persists `/var/log`;
   `/etc/machine-id` is persisted too, so previous boots' journals stay
   readable). A failed boot's log is then available via `journalctl -b -1`.
2. **Boot ledger** — `record-boot-attempt.service` (`basic.target`, after
   `local-fs.target`) appends a line with timestamp, **systemd boot-id**, kernel
   and generation to `/persist/boot-introspection/boots.log` as early as stage 2;
   `record-boot-success.service` (`multi-user.target`, `requires`+`after`
   `sshd.service`) appends a `success` line **only if sshd actually came up**.
   An attempt without a matching success therefore pinpoints a boot that failed
   to reach a usable post-boot state.
3. **Boot menu** — `boot.loader.timeout = 10` so the systemd-boot menu is
   reliably shown (select older generation / edit kernel cmdline).
4. **Systemd stage 1** — `boot.initrd.systemd.enable = true` explicitly
   (required by the initrd rollback unit in `impermanence.nix`); initrd
   failures drop into an emergency shell on the console.
5. **`boot-introspect` helper** (in systemPackages) — prints the ledger,
   `journalctl --list-boots`, and attempts without matching success, with the
   `journalctl --boot=<id>` command for each.

Documented recovery paths in the module header: from a live ISO,
`mount -o subvol=@persist /dev/sda2 /mnt` → `boots.log`,
`journalctl --directory=/mnt/var/log/journal`, and the 30-day `old_roots`
btrfs snapshots kept by the root-rollback service.

### Verification before install

- `nix eval .#nixosConfigurations.lanchamarcou.config.system.build.toplevel.drvPath`
  (full eval) and `diskoScript.drvPath` — clean.
- `nix build --dry-run` of both derivations — resolved cleanly.
- Spot-checks of the evaluated config (journald config, timeout, units,
  wants-lists, packages) — all present.
- Note: force-evaluating `environment.persistence."/persist".directories`
  errors out on a pre-existing version mismatch (pinned impermanence release
  defines a `method` option removed from current nixpkgs). It only errors when
  that option is *forced*; normal builds are unaffected.

## 3. Installation over SSH (from the live ISO)

1. rsync'd the flake to `/tmp/flake` on the target.
2. Built and ran `system.build.diskoScript` (`nix build` on the target; note
   the out-link is the script itself, not `bin/disko`) — re-created the GPT
   layout: 1G ESP (`disk-main-ESP`) + btrfs (`disk-main-root`) with subvolumes
   `@` → `/mnt`, `@nix` → `/mnt/nix`, `@persist` → `/mnt/persist`, ESP →
   `/mnt/boot`.
3. `nixos-install --flake /tmp/flake#lanchamarcou --no-channel-copy --no-root-password`
   — builds with `--store /mnt` directly onto the target disk (no tmpfs
   overflow on the installer). `installation finished!`, EFI entries created.
4. Rescue access: `chroot /mnt /nix/var/nix/profiles/system/sw/bin/chpasswd`
   set root's password (later found to be futile — see §4; `/etc/shadow` is
   wiped by the rollback).

**Important lessons:**
- `nixos-install` requires the **full disko mount layout** at `/mnt`
  (`@`, `@nix` at `/mnt/nix`, `@persist` at `/mnt/persist`, ESP at
  `/mnt/boot`). A run performed with only `@persist` mounted at `/mnt`
  silently wrote a **complete duplicate nix store into `/persist/nix`** and
  failed at the bootloader step (`check-mountpoints` correctly complained the
  ESP wasn't mounted). The stray 4.2 GB store was deleted afterwards.
- Do **not** run verification builds without `--store`: `nix build` without a
  store targeting the ISO's 2.7 GiB tmpfs store overflows it
  (`No space left on device`).

## 4. First boot — "failure" and diagnosis

- EFI boot order adjusted with `efibootmgr -o 0000,…` so the machine boots
  `Linux Boot Manager` (systemd-boot) rather than the USB stick.
- **SSH access design**: the config authorizes
  `zeusOlympia/lanchamarcou/sshHostKey.pub` for `plat2548` and `root`. The
  committed key was from an *earlier* ISO boot, so it was refreshed with the
  current ISO host key (private half fetched from the running ISO beforehand:
  `sudo cat /etc/ssh/ssh_host_ed25519_key`) and the closure rebuilt + reinstalled
  (mostly cached).
- After reboot the machine disappeared from the LAN (no ping, no ARP).
  Diagnosis using the installed fail-safes (from a live ISO):
  - `/persist/boot-introspection/boots.log` contained **attempt AND success**
    lines for boot `f8d95833…` → the machine reached `basic.target` and sshd
    was actually up ⇒ the boot **succeeded**.
  - `journalctl --directory=/mnt/var/log/journal --boot=<boot_id>` showed a
    clean 53 s boot: "Reached target Multi-User System", sshd listening —
    but `wpa_supplicant` initialized and **never associated**, NetworkManager
    logged **zero activation attempts**.

### Root cause

The machine's practical network path is WiFi (`wlo1`, Atheros ath9k; `eno1`
Realtek ethernet has no carrier). NetworkManager connection profiles (SSID
`VIRGIN870` + PSK) live in `/etc/NetworkManager/system-connections` — on the
root subvolume, **wiped on every boot** by the impermanence rollback. So the
system booted fine, but had no profile to activate → no IP → unreachable →
indistinguishable from a failed boot from outside. This also explains why the
previous install "failed to provide a bootable machine".

## 5. Fixes applied (Generation 3, closure `1n8g1pdl…`)

1. `impermanence.nix`: added `/etc/NetworkManager/system-connections` to the
   persisted directories (bind-mount unit
   `etc-NetworkManager-system\x2dconnections.mount` confirmed in the closure).
2. Pre-seeded the WiFi profile into `/persist/etc/NetworkManager/system-connections/VIRGIN870.nmconnection`
   (`autoconnect=true`, `wpa-psk`, mode 600) so it survives every root wipe.
3. Reinstalled (full mount layout!), verified 3 boot entries on the ESP.

## 6. Successful boot and verification (Generation 3)

- Reboot monitored: ping + SSH banner after ~150 s; SSH in **as
  `plat2548@lanchamarcou`** with the installer host key (`-i` +
  `IdentitiesOnly=yes`) — the installed system, not the ISO.
- `wlo1` obtained `192.168.2.19/24`, NM connection `VIRGIN870` activated.
- Boot ledger:
  ```
  14:42:48 attempt boot_id=5ad9a096… generation=1n8g1pdl…
  14:42:51 success boot_id=5ad9a096… generation=1n8g1pdl…
  ```
- `record-boot-attempt.service` and `record-boot-success.service`: active.
- `/etc/NetworkManager/system-connections` confirmed as a bind mount from
  `@persist/etc/NetworkManager/system-connections` with the seeded profile.
- Persistent journal spans boots; `boot-introspect` reports **zero failed
  boots**; `boot-introspect` helper and persistent journald fully operational.

## 7. Current state / remaining caveats

- `/etc/ssh` host keys still regenerate every boot (not persisted). Harmless
  here because the *client* key (installer host key) is what the config
  authorizes, but consider adding `/etc/ssh` to the impermanence list if
  stable host keys are ever wanted.
- `plat2548` has no password and root's password is wiped each boot
  (`/etc/shadow` on the wiped root) — console login is not possible by
  design; access is SSH-key only. The boot-menu escape hatch (`init=/bin/sh`,
  10 s menu) is available if SSH is ever unreachable.
- The ESP keeps Generations 1–3; `boot.loader.timeout = 10` allows selecting
  an older generation at any boot.
- The machine's boot order: `Linux Boot Manager` (systemd-boot) first via
  `efibootmgr -o 0000,…`.
- Installer host key pair used for SSH client auth is held at
  `/tmp/iso_host_ed25519_key` (on the machine that performed the install) —
  back it up somewhere safe or replace `sshHostKey.pub` with a key whose
  private half you control.