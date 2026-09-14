# SUMMARY — remote host telemetry (branch `remote-host-telemetry-2`)

Goal: telegraf on `augtibcalcla` and `lanchamarcou` streams telemetry into
tables (one per host) on `wranHearst`'s PostgreSQL server.

## 1. Recon

- Read `instructions.txt`, explored the repo layout: hosts are assembled by
  `heidRunOverCar/mkNixOS.nix` from per-host module lists in `empTriageCan/*.nix`
  (each list points at modules under `zeusOlympia/`).
- Discovered the session runs **on `wranHearst` itself** (hostname check), with
  PostgreSQL 18.6 already running from the existing `zeusOlympia/postgresql`
  module. No root/sudo available (`sudo` needs a password), so the system could
  not be switched in-place; testing was done as described in step 5.
- Confirmed the LAN is 192.168.2.0/24, and that `services.postgresql` on NixOS
  only listens on localhost with md5/peer hba rules by default.
- Inspected telegraf 1.39.3 (nixpkgs): `outputs.postgresql` supports
  `tags_as_jsonb` / `fields_as_jsonb` and, crucially, `name_override` is
  honored on **output** plugins (`models/running_output.go` applies it before
  write), which gives a single table per host named after the override.

## 2. Server side — `zeusOlympia/postgresql/` (imported by `wranHearst`)

- `telegraf-credentials.nix` (new): shared database name (`telemetry`), user
  (`telegraf`) and password. Imported by both the server and client side.
  *Trade-off:* the password is plain text in the repo/nix store — acceptable
  for this lab; the role is insert-only and restricted to the `telemetry`
  database, and remote auth is scram-sha-256 from private ranges only.
- `telegraf-schema.sql` (new): idempotently creates one table per host
  (`telemetry_augtibcalcla`, `telemetry_lanchamarcou`: `time timestamptz`,
  `tags jsonb`, `fields jsonb` — matching exactly what the telegraf plugin
  expects with `tags_as_jsonb`/`fields_as_jsonb` and
  `timestamp_column_type = "timestamp with time zone"`), per-host time indexes,
  and grants (`CONNECT` on the db, `USAGE` on schema public, `INSERT` on the
  two tables) to the `telegraf` role.
- `default.nix`: added the `telemetry` database to `ensureDatabases`; extended
  the idempotent `mypsql` unit to create the `telegraf` login role (DO block +
  `ALTER ROLE ... PASSWORD`), set the db owner, and apply
  `telegraf-schema.sql`; enabled `enableTCPIP` and added pg_hba rules allowing
  `telegraf` → `telemetry` via scram-sha-256 from private IPv4/IPv6 ranges
  (defaults for localhost are untouched); opened firewall port 5432.

## 3. Client side — `zeusOlympia/telegraf/` (imported by the two agent hosts)

- `default.nix`: standard `localLib.mkDirectoryImporterModule ./.` wrapper.
- `client.nix`: enables `services.telegraf` with:
  - agent: 10s interval/flush;
  - inputs: cpu, mem, swap, system, net, disk (fs ignores);
  - a starlark processor that copies the measurement name into a `measurement`
    tag (needed because `name_override` collapses all measurements into the
    per-host table, so the original input type would otherwise be lost);
  - one `outputs.postgresql` with `name_override = telemetry_<hostName>` (via
    `config.networking.hostName`, so the same module serves both hosts),
    jsonb tags/fields, timestamptz, connecting to
    `postgres://telegraf:…@wranHearst.local:5432/telemetry?sslmode=disable`.
- `zeusOlympia/avahi.nix`: added `publish.addresses = true` so `wranHearst`
  publishes its mDNS A record (`wranHearst.local` becomes resolvable for the
  agents; they already published their own addresses).
- `empTriageCan/augtibcalcla.nix` and `empTriageCan/lanchamarcou.nix`: added
  `"./telegraf"` to the module lists (wranHearst deliberately does not get it).

## 4. Build verification

- All three configurations evaluate and build:
  - `wranHearst`: telegraf disabled, postgresql enabled, `listen_addresses="*"`,
    firewall `[22, 5432]`, generated pg_hba contains the 4 scram rules above
    the localhost defaults, `mypsql-start` script contains the new telemetry
    provisioning steps.
  - `augtibcalcla` / `lanchamarcou`: telegraf enabled with correct per-host
    `name_override` (`telemetry_augtibcalcla` / `telemetry_lanchamarcou`).
- `nix build .#nixosConfigurations.{wranHearst,augtibcalcla,lanchamarcou}.config.system.build.toplevel`
  all succeed.
- Committed as `846f0ce` on branch `remote-host-telemetry-2`.

## 5. End-to-end test (no root available for `nixos-rebuild switch`)

Since `sudo` requires a password (not available in this session), the live
system could not be switched; instead the exact generated artifacts were tested
against a throwaway PostgreSQL 18.6 instance (same store package as the real
server) run from `/tmp` as user `sieyes`:

1. `initdb` a test cluster on port 5433, peer/scram auth, with the same
   telegraf pg_hba lines the module generates.
2. Created `doc`, `pi`, `telemetry` databases (normally done by
   `postgresql-setup.service` from `ensureDatabases`).
3. Ran the **exact generated `mypsql-start` script** from the built wranHearst
   closure against it — twice, to prove idempotency (second run only emits
   NOTICEs). Verified: `telegraf` role exists (non-superuser, login), correct
   scram password works over TCP, wrong password rejected.
4. Extracted the **exact generated telegraf `config.toml`** from the built
   `augtibcalcla` and `lanchamarcou` system closures (only replacing the
   target host, since the throwaway server is local), ran both telegraf
   instances for 30 s: no client errors.
5. Verified rows: `telemetry_augtibcalcla` and `telemetry_lanchamarcou` each
   received 78 rows spanning cpu/mem/swap/system/net/disk with the
   `measurement` tag preserved in `tags` (e.g.
   `{"cpu": "cpu0", "host": "…", "measurement": "cpu"}`) and numeric fields in
   `fields`.

What remains for a root session: `nixos-rebuild switch` on all three hosts;
on `wranHearst` the new `telemetry` database is then created by
`postgresql-setup` and the schema/role applied by the `mypsql` unit, and the
firewall opens 5432 (the running system predates the change, so the live
server still only listens on localhost).
