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
{
  config,
  lib,
  ...
}:
let
  mediaRoot = "/srv/media";
  mediaGroup = "media";
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
  # (prowlarr's module uses a dynamic user; it only talks HTTP to the other
  # services, so it needs no access to the media group)
  services.prowlarr.enable = true;

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
  # Jellyseerr (services.jellyseerr is the renamed-option alias of
  # services.seerr): request management UI in front of Sonarr/Radarr
  # ---------------------------------------------------------------------
  services.jellyseerr.enable = true;

  # ---------------------------------------------------------------------
  # library directories (impermanence-friendly: declared so the media root
  # exists with the right ownership even on a fresh boot)
  # ---------------------------------------------------------------------
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
}