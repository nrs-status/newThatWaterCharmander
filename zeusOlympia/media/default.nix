# Media stack for wranHearst:
#   qBittorrent (downloads) -> Prowlarr (indexer management) ->
#   Sonarr (TV) / Radarr (movies) -> Jellyfin (playback) with
#   Jellyseerr (requests) on top,
#   + ytdl-sub: YouTube channels downloaded directly into the TV library
#     as TV shows (via the "Jellyfin TV Show by Date" preset, which writes
#     NFO metadata, posters and fanart that Jellyfin reads natively).
#
# layout: qBittorrent saves to /srv/media/downloads, Sonarr/Radarr import
# from there into /srv/media/tv and /srv/media/movies, Jellyfin serves
# /srv/media. all of the service users share the "media" group so the
# download -> import -> serve chain works without permission friction
# (hence the 0002 umasks and group-writable directories below).
#
# wranHearst runs impermanence (root is wiped on reboot, see
# ../fs/impermanence.nix), so all of the stack's state (media library +
# service state dirs) is persisted under /persist explicitly (see the
# bottom of the file).
#
# the Jellyfin accounts (admin `wranHearst`, viewer `sieyes`) and the
# TV/movie libraries are set up declaratively by media-jellyfin-init.service
# on first boot (the passwords live in this file, since Jellyfin offers no
# declarative user-management option in nixpkgs).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  mediaRoot = "/srv/media";
  mediaGroup = "media";

  # completes Jellyfin's first-boot setup wizard declaratively and creates
  # the two service accounts (see the comment on the unit below).
  # The whole flow is retried until a deadline: Jellyfin restarts internally
  # while running its DB migrations (its web server answers 503/HTML while
  # starting, and even 200-then-503 in quick succession), so single-shot
  # attempts are too fragile.
  jellyfinInit = pkgs.writeShellScript "media-jellyfin-init" ''
    set -uo pipefail

    base=http://127.0.0.1:8096
    marker=${config.services.jellyfin.configDir}/.nixos-media-users-created
    curl=${lib.getExe pkgs.curl}
    jq=${lib.getExe pkgs.jq}
    sleep=${lib.getExe' pkgs.coreutils "sleep"}
    touch=${lib.getExe' pkgs.coreutils "touch"}
    seq=${lib.getExe' pkgs.coreutils "seq"}
    date=${lib.getExe' pkgs.coreutils "date"}
    grep=${lib.getExe pkgs.gnugrep}
    authHeader='Authorization: MediaBrowser Client="nixos-media", Device="nixos-media", DeviceId="nixos-media", Version="1.0"'

    [ -f "$marker" ] && exit 0

    run_flow() (
      set -euo pipefail

      # wait until Jellyfin answers a *valid* public info response (its web
      # server is up early but answers 503/HTML while migrating)
      ready=""
      for i in $($seq 1 150); do
        if out=$($curl -fsS "$base/System/Info/Public" 2>/dev/null) \
          && echo "$out" | $jq -e 'has("StartupWizardCompleted")' >/dev/null 2>&1; then
          ready=1
          break
        fi
        $sleep 2
      done
      if [ -z "$ready" ]; then
        echo "media-jellyfin-init: Jellyfin did not become ready in time" >&2
        return 1
      fi

      wizardCompleted=$($curl -fsS "$base/System/Info/Public" | $jq -r '.StartupWizardCompleted // false')
      fresh=0
      if [ "$wizardCompleted" != "true" ]; then
        # finish the first-boot setup wizard: the user created here becomes
        # the administrator. GET /Startup/User first: on a fresh database no
        # user exists yet, and POST /Startup/User only *updates* the first
        # user (renaming it + setting the password) — it is the GET that
        # triggers the manager's InitializeAsync, which seeds the placeholder
        # first user
        $curl -fsS -X POST "$base/Startup/Configuration" \
          -H 'Content-Type: application/json' \
          -d '{"UICulture":"en-US","MetadataCountryCode":"US","PreferredMetadataLanguage":"en"}'
        $curl -fsS "$base/Startup/User" >/dev/null
        $curl -fsS -X POST "$base/Startup/User" \
          -H 'Content-Type: application/json' \
          -d '{"Name":"wranHearst","Password":"whmedia"}'
        $curl -fsS -X POST "$base/Startup/Complete"
        fresh=1
      fi

      # authenticate the admin account so we can manage users/libraries
      token=$($curl -fsS -X POST "$base/Users/AuthenticateByName" \
        -H "$authHeader" -H 'Content-Type: application/json' \
        -d '{"Username":"wranHearst","Pw":"whmedia"}' | $jq -r '.AccessToken // empty') || token=""
      if [ -z "$token" ]; then
        if [ "$fresh" = 1 ]; then
          echo "media-jellyfin-init: could not authenticate the just-created admin user" >&2
          return 1
        fi
        echo "media-jellyfin-init: wizard already completed and the configured admin" >&2
        echo "password was rejected (changed outside this configuration?); skipping" >&2
        return 0
      fi
      apiHeader="Authorization: MediaBrowser Token=\"$token\""

      # non-admin account for regular viewers (created with the default
      # policy, i.e. no administrator rights)
      if ! $curl -fsS -H "$apiHeader" "$base/Users" | $jq -r '.[].Name' | $grep -qx sieyes; then
        $curl -fsS -X POST "$base/Users/New" -H "$apiHeader" \
          -H 'Content-Type: application/json' \
          -d '{"Name":"sieyes","Password":"sieyesmedia"}'
      fi

      # make sure the library folders exist so accounts can actually watch
      # something; skipped if Jellyfin already has libraries (manual setup)
      folders=$($curl -fsS -H "$apiHeader" "$base/Library/VirtualFolders") || folders=""
      if [ -n "$folders" ]; then
        if ! echo "$folders" | $jq -r '.[].Name' | $grep -qx 'Series'; then
          $curl -fsS -X POST "$base/Library/VirtualFolders?name=Series&collectionType=tvshows" \
            -H "$apiHeader" -H 'Content-Type: application/json' \
            -d '{"LibraryOptions":{"PathInfos":[{"Path":"${mediaRoot}/tv"}]}}'
        fi
        if ! echo "$folders" | $jq -r '.[].Name' | $grep -qx 'Movies'; then
          $curl -fsS -X POST "$base/Library/VirtualFolders?name=Movies&collectionType=movies" \
            -H "$apiHeader" -H 'Content-Type: application/json' \
            -d '{"LibraryOptions":{"PathInfos":[{"Path":"${mediaRoot}/movies"}]}}'
        fi
      fi
    )

    # retry until a deadline (jellyfin keeps restarting while migrating on a
    # fresh boot); every step is guarded/idempotent, so retrying is safe
    deadline=$(( $($date +%s) + 600 ))
    while true; do
      if run_flow; then
        $touch "$marker"
        exit 0
      fi
      if [ "$( $date +%s )" -ge "$deadline" ]; then
        echo "media-jellyfin-init: giving up after 10 minutes" >&2
        exit 1
      fi
      $sleep 5
    done
  '';
in
{
  users.groups.${mediaGroup} = { };

  # ---------------------------------------------------------------------
  # qBittorrent (qbittorrent-nix): headless torrent client
  # ---------------------------------------------------------------------
  services.qbittorrent = {
    enable = true;
    group = mediaGroup;
    webuiPort = 8080;
    # accept the legal notice and keep everything under /srv/media
    serverConfig = {
      LegalNotice.Accepted = true;
      Session = {
        # default torrent save location
        SavePath = "${mediaRoot}/downloads";
        # don't touch files that are being seeded from the completed dir
        TorrentContentLayout = "Original";
      };
      Preferences.Downloads.SavePath = "${mediaRoot}/downloads";
    };
  };
  # make qBittorrent's downloaded files group-writable so Sonarr/Radarr can
  # move (not just read) them during import
  systemd.services.qbittorrent.serviceConfig.UMask = "0002";

  # ---------------------------------------------------------------------
  # Prowlarr: indexer manager; pushes indexers to Sonarr/Radarr
  # ---------------------------------------------------------------------
  services.prowlarr.enable = true;
  # the prowlarr module uses a DynamicUser; its StateDirectory setup cannot
  # work through an impermanence bind mount (systemd's move-mount dance for
  # dynamic users fails with "Device or resource busy"), so give it a
  # static user instead — with a static user systemd just chowns the (already
  # bind-mounted, hence persisted) state directory, like for sonarr/radarr
  users.users.prowlarr = {
    isSystemUser = true;
    group = "prowlarr";
  };
  users.groups.prowlarr = { };
  systemd.services.prowlarr.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = "prowlarr";
    Group = "prowlarr";
    StateDirectory = lib.mkForce "prowlarr";
  };

  # ---------------------------------------------------------------------
  # Sonarr / Radarr: TV series + movie library managers
  # ---------------------------------------------------------------------
  services.sonarr = {
    enable = true;
    group = mediaGroup;
  };
  # imported files stay group-writable for the rest of the media group
  systemd.services.sonarr.serviceConfig.UMask = lib.mkForce "0002";
  services.radarr = {
    enable = true;
    group = mediaGroup;
  };
  systemd.services.radarr.serviceConfig.UMask = lib.mkForce "0002";

  # ---------------------------------------------------------------------
  # Jellyfin: media server
  # ---------------------------------------------------------------------
  services.jellyfin = {
    enable = true;
    group = mediaGroup;
  };
  # Jellyfin only needs to read the media library
  users.users.jellyfin.extraGroups = [ mediaGroup ];

  # declarative Jellyfin accounts: completes the first-boot setup wizard and
  # creates the admin user `wranHearst` (password `whmedia`) and the regular
  # (non-admin) viewer `sieyes` (password `sieyesmedia`), then registers the
  # TV/movie library folders. The media library lives on a persisted
  # directory (see below), so the Jellyfin database is written there too and
  # everything survives reboots.
  #
  # Runs as a separate oneshot *after* jellyfin.service (Jellyfin's unit has
  # TimeoutSec=15, too short for polling a server that may take a while to
  # listen). A marker file in the (persisted) config dir makes it a no-op
  # after the first successful run; if a pre-existing install rejects the
  # declarative admin password the unit just logs and exits 0 instead of
  # breaking Jellyfin on every boot.
  systemd.services.jellyfin.wants = [ "media-jellyfin-init.service" ];
  systemd.services.media-jellyfin-init = {
    description = "declaratively set up Jellyfin users and libraries";
    after = [ "jellyfin.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = config.services.jellyfin.user;
      Group = config.services.jellyfin.group;
      RemainAfterExit = true;
    };
    # the writeShellScript-generated script is referenced as a store path
    serviceConfig.ExecStart = "${jellyfinInit}";
  };

  # ---------------------------------------------------------------------
  # ytdl-sub: download YouTube channels into the TV library
  # ---------------------------------------------------------------------
  # Runs every 6 hours and drops each subscribed channel into
  # ${mediaRoot}/tv/<Channel Name>/Season <year>/... using ytdl-sub's
  # "Jellyfin TV Show by Date" preset (episodes numbered by upload date,
  # with tvshow.nfo / episode .nfo files, poster.jpg and fanart.jpg), so
  # Jellyfin picks them up as regular TV shows in the existing Series
  # library — no extra library configuration needed.
  #
  # To add a channel, add an entry under subscriptions below and rebuild:
  #   subscriptions.youtube_channels_as_tv_shows."Channel Name" =
  #     "https://www.youtube.com/@ExampleChannel";
  services.ytdl-sub.group = mediaGroup; # primary group "media": everything
  # ytdl-sub writes into the TV library is automatically owned by the
  # media group, like the rest of the stack
  services.ytdl-sub.instances.youtube_tv = {
    enable = true;
    schedule = "0/6:0"; # every 6 hours
    # ytdl-sub writes straight into the Sonarr-managed TV library; the
    # service itself is heavily sandboxed (ProtectSystem=strict), so the
    # output directory must be whitelisted explicitly.
    readWritePaths = [ "${mediaRoot}/tv" ];
    # extend the prebuilt preset (redefining it by name is rejected by
    # ytdl-sub) and point its output at the TV library
    config.presets.youtube_channels_as_tv_shows = {
      preset = [ "Jellyfin TV Show by Date" ];
      overrides.tv_show_directory = "${mediaRoot}/tv";
    };
    subscriptions.youtube_channels_as_tv_shows = {
      # "Channel Name" = "https://www.youtube.com/@ExampleChannel";
    };
  };
  # keep downloaded files group-writable like the rest of the stack
  systemd.services."ytdl-sub-youtube_tv".serviceConfig.UMask = "0002";

  # ---------------------------------------------------------------------
  # Seerr (services.jellyseerr is the renamed-option alias of
  # services.seerr): request management UI in front of Sonarr/Radarr
  # ---------------------------------------------------------------------
  services.seerr.enable = true;
  # same reason as prowlarr above: the seerr module's DynamicUser cannot
  # survive the impermanence bind mount of its state directory, so run it
  # as a static user instead
  users.users.seerr = {
    isSystemUser = true;
    group = "seerr";
  };
  users.groups.seerr = { };
  systemd.services.seerr.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = "seerr";
    Group = "seerr";
    StateDirectory = lib.mkForce "seerr";
  };

  # (see the impermanence block below for why this tmpfiles block is kept
  # alongside it)
  systemd.tmpfiles.settings."10-media-root" = {
    "${mediaRoot}"."d" = {
      mode = "0775";
      user = "root";
      group = mediaGroup;
    };
    "${mediaRoot}/downloads"."d" = {
      mode = "0775";
      user = "qbittorrent";
      group = mediaGroup;
    };
    "${mediaRoot}/tv"."d" = {
      mode = "0775";
      user = "sonarr";
      group = mediaGroup;
    };
    "${mediaRoot}/movies"."d" = {
      mode = "0775";
      user = "radarr";
      group = mediaGroup;
    };
  };

  # ---------------------------------------------------------------------
  # impermanence: wranHearst wipes its root on every reboot (see
  # ../fs/impermanence.nix), so all state of this stack must be persisted
  # explicitly under /persist:
  #   - the media library itself (/srv/media, incl. downloads/tv/movies)
  #   - the per-service state directories (databases, configs, API keys,
  #     torrent state, ytdl-sub subscription state)
  #
  # The previous systemd.tmpfiles block that created ${mediaRoot} (and the
  # downloads/tv/movies subdirectories) on every boot was evaluated against
  # the impermanence declarations below, and the result is: mostly
  # redundant, but not entirely — so it is kept (with a trimmed role).
  #
  # Impermanence creates every persisted backing directory on a fresh boot
  # with the user/group/mode declared on its entry — but only *at creation
  # time* (create-directories.bash skips existing directories), and
  # directories that are parents of other persisted entries are created
  # first, in a "parent" pass with *default* permissions (root:root 0755).
  # ${mediaRoot} is exactly such a parent (of the
  # downloads/tv/movies entries below), so its declared root:media 0775 is
  # never applied on a fresh boot — the tmpfiles block below re-asserts
  # ownership/mode on every boot (it runs after the bind mounts, i.e. on
  # the persisted tree, so the fix itself persists). For the
  # subdirectories tmpfiles is pure redundancy (impermanence creates them
  # with the right ownership), but re-asserting is idempotent and cheap,
  # and keeps the ownership documented in exactly one shape.
  #
  # NOTE: the service users referenced below (qbittorrent, sonarr, radarr)
  # are declared by this module, and impermanence's directory-creation
  # activation runs after users/groups, so they always exist by then.
  # ---------------------------------------------------------------------
  environment.persistence."/persist".directories =
    let
      # persisted directory with explicit ownership/mode
      d = directory: user: group: mode: { inherit directory user group mode; };
    in
    [
      # media library
      (d mediaRoot "root" mediaGroup "0775")
      (d "${mediaRoot}/downloads" "qbittorrent" mediaGroup "0775")
      (d "${mediaRoot}/tv" "sonarr" mediaGroup "0775")
      (d "${mediaRoot}/movies" "radarr" mediaGroup "0775")

      # qBittorrent: profile/config dir (default --profile directory)
      "/var/lib/qBittorrent"
      # Sonarr / Radarr: dataDir defaults (/var/lib/<name>/.config/... for
      # sonarr/radarr, managed via StateDirectory=<name>)
      "/var/lib/sonarr"
      "/var/lib/radarr"
      # Prowlarr: state dir (module runs as a static user now, see above,
      # so systemd chowns the bind-mounted StateDirectory normally)
      "/var/lib/prowlarr"
      # Jellyfin: dataDir (configDir = dataDir/config) + cache + logs
      "/var/lib/jellyfin"
      "/var/cache/jellyfin"
      "/var/log/jellyfin"
      # Seerr (services.jellyseerr alias): state dir; the module runs as a
      # static user now (see above) and its configDir defaults to
      # /var/lib/seerr for stateVersion >= 26.05 (26.11 on wranHearst), so
      # that single directory is all of its state
      "/var/lib/seerr"
      # ytdl-sub instances: StateDirectory=ytdl-sub/<instance> (download
      # state, subscription caches); the instance unit is
      # ytdl-sub-youtube_tv
      "/var/lib/ytdl-sub"
    ];
}