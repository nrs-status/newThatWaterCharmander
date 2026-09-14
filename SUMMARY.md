# Summary: Add a Vaultwarden service module to wranHearst

Branch: `vaultwarden`

## Steps

1. **Explored the repo structure**
   - `flake.nix` builds `nixosConfigurations` via `heidRunOverCar.mkNixOS`, with host
     modules selected per host in `empTriageCan/*.nix` (module files are listed as
     strings relative to `zeusOlympia/`, the `modulesPath`).
   - Studied existing service modules (`garage`, `forgejo`, `harmonia`, `postgresql`,
     `avahi.nix`) to match the repo's conventions: firewall ports, mDNS advertisement,
     impermanence persistence, comments.

2. **Created the Vaultwarden module at `zeusOlympia/vaultWarden/default.nix`**
   - `services.vaultwarden.enable = true` with `dbBackend = "sqlite"` (single-node,
     LAN-only deployment; no postgres backend needed).
   - `config`: `ROCKET_ADDRESS = "0.0.0.0"` (LAN reachable), `ROCKET_PORT = 8222`,
     `SIGNUPS_ALLOWED = false`, admin panel left disabled (no `ADMIN_TOKEN`).
   - `networking.firewall.allowedTCPPorts = [ 8222 ]`.
   - impermanence persistence: `environment.persistence."/persist".directories =
     [ "/var/lib/vaultwarden" ]` (wranHearst wipes its root on every boot).
   - avahi mDNS service file advertising `_http._tcp` on port 8222, same pattern as
     garage/forgejo.

3. **Extended the host `wranHearst`** by adding `"./vaultWarden"` to the module list
   in `empTriageCan/wranHearst.nix` (only this host imports the module; the other
   hosts and the colmena hive are unaffected).

4. **Testing**
   - `git add` of the new files (nix flake evaluation requires git-tracked files).
   - Evaluated the module through the flake:
     - `services.vaultwarden.enable` → `true`
     - `services.vaultwarden.config` → `{ ROCKET_ADDRESS = "0.0.0.0"; ROCKET_PORT = 8222; SIGNUPS_ALLOWED = false; }`
     - firewall ports now include `8222`
     - persisted directories now include `/var/lib/vaultwarden`
   - Confirmed the other hosts / colmena hive still evaluate
     (`colmenaHive.nodes.{augtibcalcla,lanchamarcou}.config.networking.hostName`).
   - Built the full `nixosConfigurations.wranHearst.config.system.build.toplevel`
     successfully. (A `build-vm` boot test is not meaningful for this host: its
     disko/impermanence config expects real btrfs partitions by partlabel/UUID, so a
     stock VM image cannot satisfy it.)
   - Inspected the generated `vaultwarden.service` in the toplevel: this exposed an
     initial mistake — the nixos module uses `StateDirectory=vaultwarden` /
     `DATA_FOLDER=/var/lib/vaultwarden`, not `/var/lib/bitwarden`. Fixed the
     impermanence path in the module and rebuilt the toplevel successfully.
   - Functional smoke test: ran the exact `ExecStart` binary from the toplevel
     (`vaultwarden 1.37.1`) with the unit's env file, pointing `DATA_FOLDER` at a
     temp dir and `ROCKET_PORT=8223` to avoid clashing with anything on the host:
     - `GET /` → `200`, `GET /api/config` → `200` (web vault served)
     - process stayed alive, `db.sqlite3` + `rsa_key.pem` created in the data folder.

5. **Committed** the two files (`zeusOlympia/vaultWarden/default.nix`,
   `empTriageCan/wranHearst.nix`) as
   `9a76748 add vaultwarden service module to wranHearst`.
