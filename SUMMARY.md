# Un-rooting the media stack (`zeusOlympia/media`)

Goal: no service defined by the media module may run with root privileges for
any continuous period, while every service keeps working exactly as before.

Branch: `unroot-media`

## 1. Reconnaissance

- Read `instructions.txt` and `zeusOlympia/media/default.nix`.
- Listed every systemd service the module defines/overrides and queried its
  effective `User`/`Group` from the flake evaluation:

  ```
  nix eval --raw .#nixosConfigurations.wranHearst.config.systemd.services."<unit>".serviceConfig.User
  ```

  Result before the change:

  | unit | user |
  |------|------|
  | qbittorrent | qbittorrent |
  | prowlarr | prowlarr |
  | sonarr | sonarr |
  | radarr | radarr |
  | jellyfin | jellyfin |
  | seerr | seerr |
  | ytdl-sub-youtube_tv | ytdl-sub |
  | media-jellyfin-init | jellyfin |
  | media-jellyfin-tree-heal | jellyfin |
  | **media-seerr-init** | **(none ⇒ root)** |
  | **media-arr-init** | **(none ⇒ root)** |

- The long-running services were already unprivileged, but the two
  bootstrapping oneshots (`media-seerr-init`, `media-arr-init`) ran as root
  for their whole (retrying, up to 15 min) lifetime. Those were the actual
  root-holding services.
- `ytdl-sub` already ran as its own unprivileged user in the evaluated
  configuration; to make this explicit/robust (and to document intent) its
  user is now set explicitly rather than relying on the upstream default.

## 2. Changes in `zeusOlympia/media/default.nix`

1. **New unprivileged bootstrap account**
   - Added `mediaInitUser = "media-init"` and `mediaInitStateDir =
     "/var/lib/media-init"`.
   - Declared `users.users.media-init` (`isSystemUser = true`, primary group
     `media`) so it can read the group-readable *arr config files without
     root.
2. **`media-seerr-init` runs as `media-init`**
   - `serviceConfig.User = mediaInitUser`, `Group = mediaGroup`,
     `StateDirectory = "media-init"`.
3. **`media-arr-init` runs as `media-init`**
   - Same `User`/`Group`/`StateDirectory` settings.
4. **Marker files moved out of the privileged service dirs**
   - `media-seerr-init` marker: `.nixos-media-seerr-configured` now lives in
     `/var/lib/media-init` (owned by `media-init`) instead of Seerr's config
     dir.
   - `media-arr-init` marker: `.nixos-media-arr-configured` now lives in
     `/var/lib/media-init` instead of Sonarr's data dir.
   - Both markers are still persisted (see below), so the units remain
     no-ops after a successful first run, exactly as before.
5. **Radarr data dir made group-traversable**
   - The radarr module creates `/var/lib/radarr/.config/Radarr` with mode
     `0700`. The unprivileged bootstrap must read Radarr's self-generated
     API key, so the mode is forced to `0750 radarr:media` (the same shared
     `media` group Sonarr already uses). Radarr itself does not re-chmod the
     directory, so the setting sticks.
6. **`ytdl-sub` user made explicit**
   - `services.ytdl-sub.user = "ytdl-sub";` (never root).
7. **Persistence for the new state dir**
   - Added `(d "/var/lib/media-init" "media-init" "media" "0755")` to
     `environment.persistence."/persist".directories` so the markers survive
     the root wipe.

`media-jellyfin-init` and `media-jellyfin-tree-heal` were already running as
`jellyfin` and needed no change.

## 3. Test review and update

The work was first verified only with the pre-existing media VM test. On
review that was **not sufficient** to claim an end-to-end guarantee: it
proved the services were up, unprivileged and had the right wiring *stored*,
but it never exercised the user-facing paths that unprivileging could break
(the permission chain across `/srv/media`, real download-client/indexer
connectivity, or playback). `kaounSlidesTotem/media-test/default.nix` was
therefore extended from a "services-are-up-and-wired" check into an
end-to-end check of the paths these changes can affect:

- **No root anywhere**: every service unit must report a non-empty,
  non-`root` `User` (including both bootstraps), and
  `ytdl-sub-youtube_tv.service` must run as `ytdl-sub`.
- **Wiring actually works** (config inspection is not enough):
  `downloadclient/testall` on Sonarr/Radarr (proves they can reach
  qBittorrent with the stored credentials) and `applications/testall` on
  Prowlarr (proves it can reach both *arrs).
- **The unprivileged permission chain, executed as the real service users**
  with `runuser`:
  - `qbittorrent` writes a download into `/srv/media/downloads` (umask 0002),
  - `sonarr` moves it into `/srv/media/tv`, `radarr` into `/srv/media/movies`,
  - `jellyfin` reads both,
  - `ytdl-sub` writes into `/srv/media/tv`,
  - `media-init` reads all three `config.xml` API keys and owns
    `/var/lib/media-init`,
  - both bootstraps actually created their markers in the new location.
- **Playback, end to end**: Jellyfin is asked to stream the test episode
  (`/Videos/{id}/stream?static=true`) and must return 200/206 with bytes —
  indexing is not treated as proof that the file can be served.
- The new `/var/lib/media-init` persistence is included in the bind-mount
  and reboot checks.

## 4. Verification

Ran the media VM test (offline NixOS VM with the real module, impermanence,
Jellyfin, the *arrs, Seerr and ytdl-sub):

```
nix build .#checks.x86_64-linux.media-vm-test
```

Result: **build succeeded** (`result ->
/nix/store/yicrnb5kph6h80209wfpix3yqqrj0xz5-vm-test-run-media-stack-vm-test`),
zero tracebacks. The VM test brought up every service, passed the
root-privilege assertions, completed the Jellyfin accounts/libraries flow,
exercised the full qBittorrent -> Sonarr/Radarr -> Jellyfin permission chain
and the Prowlarr/Sonarr/Radarr connectivity tests through the now
unprivileged `media-init` user, streamed a file back out of Jellyfin, and
survived a reboot with state (markers, config, library ownership) intact.

### What the VM still cannot prove (and why that is acceptable)

The test VM is deliberately offline, so it cannot exercise the
internet-dependent halves of acquisition: Prowlarr fetching Cardigann
definitions and searching a tracker, qBittorrent transferring real peers,
Sonarr/Radarr TMDB/TVDB metadata lookups, or ytdl-sub downloading from
YouTube. None of those paths were touched by this change (the only
behavioural changes are *which non-root user runs the two bootstraps*, where
their markers live, and Radarr's data-dir mode), and they are already
exercised by the live stack on wranHearst. The permission-sensitive parts
that the change could have broken — reading the API keys, writing the
markers, the download->import->serve chain, and playback — are now covered
explicitly.

## 5. Files changed

- `zeusOlympia/media/default.nix` — the un-rooting changes (+38/−2).
- `kaounSlidesTotem/media-test/default.nix` — the end-to-end test additions
  (+136): root-freedom assertions, `testall` connectivity checks, the
  `runuser` permission chain, the Jellyfin streaming check, and the
  `/var/lib/media-init` marker/persistence checks.
- `SUMMARY.md` (this file).

Nothing was committed.