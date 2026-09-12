# Configuration derivation for the Garage object store module: renders the
# TOML config file and wires up the systemd unit. See options.nix for the
# option declarations.
#
# nixpkgs ships its own (simpler) `services.garage` module; we disable it so
# this module fully owns the `services.garage` namespace (see the
# top-level `disabledModules` below).
{ config, lib, pkgs, ... }:
let
  inherit (lib) mkIf optionalString;

  cfg = config.services.garage;

  toml = pkgs.formats.toml { };
  configFile = toml.generate "garage.toml" cfg.settings;

  runtimeDir = "/run/garage";

  # Secrets are never put in the config file: they are installed into the
  # unit's private runtime directory and referenced through `*_file`
  # environment variables, which Garage natively supports. This keeps the
  # world-readable /etc/garage/garage.toml (and the Nix store) secret-free.
  secretInstall = optionalString (cfg.rpcSecretFile != null) ''
    install -m 0600 ${cfg.rpcSecretFile} ${runtimeDir}/rpc-secret
  '' + optionalString (cfg.adminTokenFile != null) ''
    install -m 0600 ${cfg.adminTokenFile} ${runtimeDir}/admin-token
  '' + optionalString (cfg.metricsTokenFile != null) ''
    install -m 0600 ${cfg.metricsTokenFile} ${runtimeDir}/metrics-token
  '';

  secretEnvironment = {
    GARAGE_RPC_SECRET_FILE = mkIf (cfg.rpcSecretFile != null) "${runtimeDir}/rpc-secret";
    GARAGE_ADMIN_TOKEN_FILE = mkIf (cfg.adminTokenFile != null) "${runtimeDir}/admin-token";
    GARAGE_METRICS_TOKEN_FILE = mkIf (cfg.metricsTokenFile != null) "${runtimeDir}/metrics-token";
  };
in
{
  disabledModules = [ "services/web-servers/garage.nix" ];

  config = mkIf cfg.enable {
  users.users.garage = {
    isSystemUser = true;
    group = "garage";
    description = "Garage object store daemon user";
  };
  users.groups.garage = { };

  # expose the garage CLI system-wide; it talks to the admin API declared in
  # /etc/garage/garage.toml
  environment.systemPackages = [ cfg.package ];

  environment.etc."garage/garage.toml".source = configFile;

  systemd.services.garage = {
    description = "Garage S3-compatible object store";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];

    environment = secretEnvironment;

    preStart = secretInstall;

    serviceConfig = {
      Type = "simple";
      User = "garage";
      Group = "garage";
      ExecStart = "${cfg.package}/bin/garage -c /etc/garage/garage.toml server";
      StateDirectory = "garage";
      StateDirectoryMode = "0750";
      RuntimeDirectory = "garage";
      RuntimeDirectoryMode = "0700";
      Restart = "on-failure";
      RestartSec = "5s";
      LimitNOFILE = 65536;
      UMask = "0077";

      # hardening
      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateTmp = true;
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectHome = true;
      ProtectHostname = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ "/var/lib/garage" runtimeDir ];
      RestrictAddressFamilies = [
        "AF_UNIX"
        "AF_INET"
        "AF_INET6"
      ];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      LockPersonality = true;
      SystemCallArchitectures = "native";
    };
  };
};
}
