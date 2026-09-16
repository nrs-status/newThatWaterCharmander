{
  config,
  pkgs,
  ...
}:
let
  # credentials for the telemetry stream into wranHearst's postgresql server
  # (see ../postgresql, which provisions the database, tables and role)
  credentials = import ../postgresql/telegraf-credentials.nix;

  # the outputs.postgresql plugin only stores the measurement name as the
  # table name; with a single per-host table (name_override below) the
  # original measurement name would be lost, so this starlark processor
  # preserves it as a tag (metric.tags.measurement) inside the tags jsonb
  measurementTag =
    pkgs.writeText "telegraf-add-measurement-tag.star" ''
      def apply(metric):
          metric.tags["measurement"] = metric.name
          return metric
    '';
in
{
  services.telegraf = {
    enable = true;

    extraConfig = {
      agent = {
        interval = "10s";
        round_interval = true;
        metric_batch_size = 1000;
        metric_buffer_limit = 10000;
        flush_interval = "10s";
      };

      inputs = {
        cpu = [
          {
            percpu = true;
            totalcpu = true;
          }
        ];
        mem = [ { } ];
        swap = [ { } ];
        system = [ { } ];
        net = [ { } ];
        disk = [
          {
            ignore_fs = [
              "tmpfs"
              "devtmpfs"
              "devfs"
              "iso9660"
              "overlay"
              "aufs"
              "squashfs"
            ];
          }
        ];
      };

      processors = {
        starlark = [
          { script = measurementTag; }
        ];
      };

      outputs = {
        postgresql = [
          {
            # wranHearst.tailnet.internal resolves via the headscale tailnet's
            # MagicDNS (see ../headscale); the host is enrolled into the
            # tailnet, so the connection goes over the tailscale overlay and
            # the server accepts scram-sha-256 from the tailnet range
            # (100.64.0.0/10, see ../postgresql). the old mDNS name
            # wranHearst.local is no longer used anywhere.
            connection = "postgres://${credentials.telegrafUser}:${credentials.telegrafPassword}@${config.tailnet.magicFqdn}:5432/${credentials.telegrafDatabase}?sslmode=disable";
            # one table per host on wranHearst (telemetry_augtibcalcla /
            # telemetry_lanchamarcou, created by ../postgresql's schema)
            name_override = "telemetry_${config.networking.hostName}";
            tags_as_jsonb = true;
            fields_as_jsonb = true;
            timestamp_column_type = "timestamp with time zone";
          }
        ];
      };
    };
  };
}
