# Media stack for wranHearst

This module turns wranHearst into a self-service media box. If you are not
an administrator, here is all you need to know.

## Where to point your browser

| What you want                | URL (on the tailnet)      |
|------------------------------|---------------------------|
| Watch something              | http://wranHearst:8096  (Jellyfin) |
| Request something new        | http://wranHearst:5055  (Seerr)    |
| Request a YouTube channel    | ask an admin (see below)  |

Everything else (qBittorrent, Prowlarr, Sonarr, Radarr) is plumbing — you
never need to touch it.

## Watching (Jellyfin)

1. Open http://wranHearst:8096.
2. Log in with your Jellyfin account:
   - `wranHearst` (password `whmedia`) — the administrator account, or
   - `sieyes` (password `sieyesmedia`) — a regular viewer account.

   Both are created automatically on first boot by the media module (see
   `zeusOlympia/media/default.nix`); use "Sign in with Jellyfin" in the
   Seerr/quick-connect flows with the same credentials.
3. Pick the **Series** library. Every managed show lives there — click an
   episode and press play. Subtitle and audio tracks are selectable in the
   player; playback works in the browser, in the official Jellyfin apps, and
   with any client that can stream from Jellyfin.

(There is no manual first-boot wizard: the media module completes it and
 registers the Series/Movies libraries automatically.)

## Requesting something that isn't there yet (Seerr)

1. Open http://wranHearst:5055 and log in (first time: it authenticates
   against Jellyfin).
2. Search for the series or movie, press **Request**.
3. That's it. Behind the scenes Seerr tells Sonarr (series) or Radarr
   (movies); they search the indexers, hand the torrent to qBittorrent, and
   once the download finishes the episode/film is imported and shows up in
   Jellyfin automatically — usually minutes later, depending on seeds.
   Seerr will show the status of your request (downloading → available) and
   can notify you when it's ready.

## YouTube channels as TV shows (ytdl-sub)

YouTube channels are downloaded automatically and appear in Jellyfin's
**Series** library like any other show: one folder per channel, one season
per year (episodes are numbered by upload date), with cover art and episode
descriptions. New videos are picked up every 6 hours.

To get a channel added, ask an administrator. Adding one is a two-line
change in `zeusOlympia/media/default.nix` followed by a rebuild:

```nix
subscriptions.youtube_channels_as_tv_shows = {
  "Channel Name" = "https://www.youtube.com/@ExampleChannel";
};
```

## Things only the admin does (not you)

- running `sudo nixos-rebuild switch` after this module changes
- adding/removing indexers in Prowlarr and giving out accounts

(First-boot setup of Jellyfin — the wizard, the accounts and the
 Series/Movies libraries — happens automatically on first boot.)

## Where the files live (read-only for you)

- TV: `/srv/media/tv` — one folder per series (including YouTube
  channels, which are downloaded there by `ytdl-sub`)
- Movies: `/srv/media/movies`
- In-flight downloads: `/srv/media/downloads` (deleted after import)

If you want to play a file with a local player instead (e.g. `mpv`), stream
it straight from Jellyfin:

    mpv "http://wranHearst:8096/Videos/<itemId>/stream?static=true&api_key=<yourApiKey>"

— or just copy it from `/srv/media`, it is group-readable for the whole
`media` group.
