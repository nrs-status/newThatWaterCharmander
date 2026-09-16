{
  config,
  pkgs,
  ...
}:
let
  vaultwardenPort = 8222;
in
{
  services.vaultwarden = {
    enable = true;
    package = pkgs.vaultwarden;

    # the nixos module
    # stores the state in /var/lib/vaultwarden (services.vaultwarden default:
    # StateDirectory=vaultwarden / DATA_FOLDER), persisted below
    dbBackend = "postgresql";

    config = {
      ROCKET_ADDRESS = "0.0.0.0"; # reachable from the LAN
      ROCKET_PORT = vaultwardenPort;

      # dbBackend = "postgresql" only builds the binary with the postgres
      # feature (no sqlite fallback); without DATABASE_URL vaultwarden would
      # try its default sqlite data/db.sqlite3 and crash on startup. the
      # connection goes through the local unix socket, so the vaultwarden
      # role authenticates via peer auth (see services.postgresql below and
      # ../postgresql)
      DATABASE_URL = "postgresql:///vaultwarden?host=/run/postgresql";

      # signups are managed manually by the admin; the admin panel is enabled
      # by the ADMIN_TOKEN secret provided through the sops-rendered
      # environment file (see below)
      SIGNUPS_ALLOWED = false;
    };

    # the admin token (ADMIN_TOKEN) is managed with sops-nix (see the sops
    # declaration below) and rendered into an environment file; it must never
    # be put in `config`, which the upstream module renders into a
    # world-readable store path (config.env). the upstream module sources
    # this file via its EnvironmentFile, so the admin panel is enabled
    # without any further configuration.
    environmentFile = config.sops.templates."vaultwarden-env".path;
  };

  # the postgres backend needs a database and a role: create them on the
  # wranHearst postgres server (see ../postgresql). the role is authenticated
  # by peer auth over the unix socket (DATABASE_URL above), so no password
  services.postgresql = {
    ensureDatabases = [ "vaultwarden" ];
    ensureUsers = [
      {
        name = "vaultwarden";
        ensureDBOwnership = true;
      }
    ];
  };

  # vaultwarden secrets, decrypted from the host's sops file (same pattern as
  # ../garage). the following keys must exist in /etc/kierLeapMount/secrets.yaml
  # as a nested yaml mapping (the file is added imperatively; it is not part of
  # the repo; sops-nix splits secret names on "/" into nested keys):
  #   vaultwarden:
  #     admin-token:  any random token (an argon2 PHC string is also accepted),
  #                   e.g. `head -c 32 /dev/urandom | base64`
  # the secret is rendered into a single environment file because the
  # vaultwarden upstream module takes exactly one environmentFile. sops-nix
  # restarts vaultwarden whenever the secret is re-rendered (e.g. on a
  # rotation at nixos-rebuild)
  sops.secrets."vaultwarden/admin-token" = {
    sopsFile = "/etc/kierLeapMount/secrets.yaml";
    mode = "0400";
    restartUnits = [ "vaultwarden.service" ];
  };
  sops.templates."vaultwarden-env" = {
    mode = "0400";
    restartUnits = [ "vaultwarden.service" ];
    content = ''
      ADMIN_TOKEN=${config.sops.placeholder."vaultwarden/admin-token"}
    '';
  };

  systemd.services.vaultwarden = {
    # sops-nix decrypts the secrets at boot: on wranHearst that happens in the
    # sops-install-secrets.service unit (useSystemdActivation is set in
    # ../security); on hosts where sops-nix runs as a plain activation script
    # the unit does not exist and this ordering is a harmless no-op
    after = [
      "sops-install-secrets.service"
      # wait for the postgres server (which creates the vaultwarden database
      # and role via ensureDatabases/ensureUsers above) before connecting
      "postgresql.target"
    ];
    requires = [ "postgresql.target" ];
  };

  # the vaultwarden state must be persisted explicitly
  environment.persistence."/persist".directories = [ "/var/lib/vaultwarden" ];

  networking.firewall.allowedTCPPorts = [ vaultwardenPort ];

  # vaultwarden is reachable over the headscale tailnet (see ../headscale) as
  # wranHearst.tailnet.internal; the old mDNS (_http._tcp via services.avahi)
  # advertisement was removed
}
