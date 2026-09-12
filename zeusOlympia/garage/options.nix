# Option declarations for the Garage object store module.
#
# The daemon is configured via `services.garage.settings`, which is rendered
# into a TOML config file (see
# https://garagehq.deuxfleurs.fr/documentation/reference-manual/configuration/).
# Secrets are deliberately kept out of `settings`: they are passed to the
# daemon through `*_file` environment variables, so no secret ever lands in
# the world-readable Nix store or /etc.
{ lib, pkgs, ... }:
let
  inherit (lib)
    mkEnableOption
    mkOption
    types
    ;
in
{
  options.services.garage = {
    enable = mkEnableOption ''
      the Garage S3-compatible object store. The daemon listens on the ports
      declared in `services.garage.settings` (S3 API on 3900, cluster RPC on
      3901, admin API on 3903 by default).
    '';

    package = mkOption {
      type = types.package;
      default = pkgs.garage;
      defaultText = "pkgs.garage";
      description = "The Garage package to use.";
    };

    rpcSecretFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = "/run/secrets/garage/rpc-secret";
      description = ''
        Path to a file containing the cluster RPC secret (a 32-byte
        hex-encoded string, e.g. generated with `openssl rand -hex 32`).
        All nodes of a cluster must share the same value. The file is
        installed into the unit's private runtime directory with mode 0600
        before the daemon starts, and passed via `GARAGE_RPC_SECRET_FILE`.
      '';
    };

    adminTokenFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = "/run/secrets/garage/admin-token";
      description = ''
        Path to a file containing the admin API token. Grants full control
        over the Garage cluster through the admin API (port 3903 by default)
        and to the `garage` CLI. The file is installed into the unit's
        private runtime directory with mode 0600 before the daemon starts,
        and passed via `GARAGE_ADMIN_TOKEN_FILE`.
      '';
    };

    metricsTokenFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Path to a file containing the token required to scrape
        `GET /metrics` on the admin API. The file is installed into the
        unit's private runtime directory with mode 0600 before the daemon
        starts, and passed via `GARAGE_METRICS_TOKEN_FILE`.
      '';
    };

    settings = mkOption {
      description = ''
        Garage daemon configuration, rendered to `garage.toml`
        (`/etc/garage/garage.toml`). Options declared below have defaults;
        any other Garage configuration key can be set as a freeform
        attribute.
      '';
      type = types.submodule {
        freeformType = (pkgs.formats.toml { }).type;
        options = {
          metadata_dir = mkOption {
            type = types.str;
            default = "/var/lib/garage/meta";
            description = "Directory for Garage's metadata (backed by StateDirectory).";
          };
          data_dir = mkOption {
            type = types.str;
            default = "/var/lib/garage/data";
            description = "Directory for stored blocks (backed by StateDirectory).";
          };
          db_engine = mkOption {
            type = types.str;
            default = "lmdb";
            description = "Metadata database engine.";
          };
          replication_factor = mkOption {
            type = types.ints.positive;
            default = 1;
            description = ''
              Number of replicas kept for each object. Must be identical on
              all nodes of a cluster.
            '';
          };
          rpc_bind_addr = mkOption {
            type = types.str;
            default = "[::]:3901";
            description = "Address and port for inter-cluster RPC traffic.";
          };
          s3_api = mkOption {
            description = "S3 API endpoint configuration.";
            type = types.submodule {
              freeformType = (pkgs.formats.toml { }).type;
              options = {
                api_bind_addr = mkOption {
                  type = types.str;
                  default = "[::]:3900";
                  description = "Address and port of the S3 API endpoint.";
                };
                s3_region = mkOption {
                  type = types.str;
                  default = "garage";
                  description = "S3 region name.";
                };
              };
            };
            default = { };
          };
          admin = mkOption {
            description = "Admin API configuration.";
            type = types.submodule {
              freeformType = (pkgs.formats.toml { }).type;
              options = {
                api_bind_addr = mkOption {
                  type = types.str;
                  default = "[::]:3903";
                  description = "Address and port of the admin API endpoint.";
                };
              };
            };
            default = { };
          };
        };
      };
      default = { };
    };
  };
}
