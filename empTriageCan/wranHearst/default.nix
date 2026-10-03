{ localModules, localLib, ... }:
{
  imports = [
    ../wranHearst-gui
    (localLib.mkDirectoryImporterModule ./.)
  ]
  ++ (with localModules; [
    forgejo
    garage
    media
    harmonia
    openBao
    postgresql
    vaultWarden
    xandikos
  ]);

  # disable the media stack (Jellyfin, Sonarr/Radarr/Prowlarr, qBittorrent,
  # Seerr, ytdl-sub): the media module is self-gating via `media.enable`
  # (default false); set it explicitly here so the disabled state is visible
  # where the module is imported
  media.enable = false;
}
