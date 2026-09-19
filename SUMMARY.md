# Fix: approved Seerr requests never reached qBittorrent/Jellyfin

Branch: `fix-seerr`

## Problem

The Seerr UI showed an approved request for the movie *Obsession*, but the
movie never appeared in qBittorrent and therefore never showed up in Jellyfin.

## Investigation

I inspected the running stack on `wranHearst` through the services' APIs
(API keys read from the services' `config.xml` / the world-readable Seerr
`settings.json`):

- Seerr was initialized and had Sonarr + Radarr registered, and the request
  had in fact been added to Radarr (`/api/v3/movie` contained *Obsession*,
  `hasFile: false`).
- Radarr's log showed why nothing downloaded:
  - `ReleaseSearchService Searching indexers for [Obsession]. 0 active indexers`
  - `FetchAndParseRssService No available indexers. check your configuration.`
- `GET /api/v3/downloadclient` on both Sonarr and Radarr returned `[]`
  (no download client), and `GET /api/v3/indexer` returned `[]`
  (no indexer).
- Prowlarr had no indexers and no applications either.

So `media-seerr-init` only registered Sonarr/Radarr *in Seerr*. The *arrs
themselves were never given a download client or an indexer, so an approved
request was accepted and added to Radarr, but the search found nothing and
no torrent was ever handed to qBittorrent.

A second, smaller gap: the Jellyfin Series/Movies libraries had
`EnableRealtimeMonitor = false`, so even after a successful import Jellyfin
did not notice the new file until its scheduled scan.

## Changes

### `zeusOlympia/media/default.nix`

- Added a declarative bootstrap unit `media-arr-init` (script built with
  `pkgs.writeShellScript`, same pattern as the existing `media-seerr-init` /
  `media-jellyfin-init` units). On first boot it:
  1. reads the Sonarr/Radarr/Prowlarr API keys from their `config.xml`,
  2. creates/updates the qBittorrent download client on Sonarr and Radarr
     (host `127.0.0.1`, port `8085`, the declarative WebUI credentials,
     categories `sonarr`/`radarr`),
  3. registers Sonarr and Radarr as Prowlarr applications
     (`prowlarrUrl` = the local Prowlarr), and
  4. adds the public indexers listed in the new `prowlarrIndexers` list
     (default: `thepiratebay`) to Prowlarr.
  It then triggers `ApplicationIndexerSync`, so Prowlarr immediately pushes
  its indexer to both *arrs. The unit is idempotent, guarded by a marker
  under the persisted Sonarr config dir, and retries with a 15 minute
  deadline (the services are still starting on a fresh boot). If Prowlarr
  has not downloaded a configured indexer definition yet, that indexer is
  logged and skipped instead of failing the whole unit, so the essential
  download-client/application wiring always gets applied.

- `media-jellyfin-init` now enables `EnableRealtimeMonitor` on the Series and
  Movies libraries (both when creating them and by updating already-existing
  libraries in place via `POST /Library/VirtualFolders/LibraryOptions`), so
  imported files appear in Jellyfin within seconds. Its marker file name was
  bumped to `.nixos-media-users-created-v2` so existing installs (whose
  libraries were created with realtime monitoring off) run the script once
  more and pick up the new option.

- Added explicit `qbittorrentUser` / `qbittorrentPassword` variables (kept in
  sync with the Jellyfin admin credentials and the qBittorrent WebUI PBKDF2
  hash) and a top-of-file comment describing the declarative wiring.

### `kaounSlidesTotem/media-test/default.nix`

Extended the media VM test to wait for `media-arr-init.service` and assert
that:
- Sonarr and Radarr each have exactly one enabled `QBittorrent` download
  client pointed at `127.0.0.1:8085` with the `sonarr`/`radarr` category,
- Prowlarr knows Sonarr and Radarr as applications,
- the wiring survives a reboot (persisted marker + state).

The public-indexer check is intentionally not asserted in the test because
the offline test VM cannot reach `indexers.prowlarr.com` to download
Prowlarr's Cardigann definitions (the `media-arr-init` script logs and skips
it there). That part was verified against the real stack instead.

### `zeusOlympia/media/README.md`

Updated the first-boot description and the "things only the admin does"
section to reflect the new automatic download-client/indexer wiring and
realtime monitoring.

## Verification

1. `nix-instantiate --parse zeusOlympia/media/default.nix` and
   `nix build .#nixosConfigurations.wranHearst.config.system.build.toplevel`
   both succeed.
2. The full VM test passes:
   `nix build .#checks.x86_64-linux.media-vm-test`
   (`run the VM test script` finished with exit code 0).
3. Live end-to-end check on `wranHearst`:
   - ran the generated `media-arr-init` script against the live services
     (both create-from-scratch and idempotent-update paths),
   - `Radarr`/`Sonarr` now list the `qBittorrent` download client,
     `Prowlarr` lists the `Radarr`/`Sonarr` applications and
     `The Pirate Bay` indexer, and both *arrs list the synced
     `The Pirate Bay (Prowlarr)` Torznab indexer,
   - triggered `MoviesSearch` for *Obsession*: Radarr grabbed a release,
     qBittorrent downloaded it (`category=radarr`, 100%) and Radarr imported
     it to `/srv/media/movies/Obsession (2026)/`,
   - Jellyfin now has realtime monitoring enabled and lists the movie.

## Applying

The configuration fix is what is committed here. Run

```
sudo nixos-rebuild switch
```

on `wranHearst` to activate it declaratively (forcing the one-time
`media-arr-init` run; the existing marker-less state means it runs on the
next boot/activation).