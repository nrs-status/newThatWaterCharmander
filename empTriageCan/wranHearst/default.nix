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

  # these modules are self-gating via `<name>.enable` (default false), the
  # same pattern as `media.enable`: each service can be toggled off with a
  # single line here, without removing the import. all six are enabled on
  # wranHearst; set one to false to disable it entirely (no service, no
  # firewall ports, no sops secrets and no impermanence entries).
  forgejo.enable = false;
  garage.enable = false;
  openbao.enable = false;
  postgresql.enable = false;
  vaultwarden.enable = false;
  xandikos.enable = false;

  # disable the media stack (Jellyfin, Sonarr/Radarr/Prowlarr, qBittorrent,
  # Seerr, ytdl-sub): the media module is self-gating via `media.enable`
  # (default false); set it explicitly here so the disabled state is visible
  # where the module is imported
  media.enable = false;
}
