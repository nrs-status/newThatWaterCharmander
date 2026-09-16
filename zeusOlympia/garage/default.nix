{
  config,
  pkgs,
  ...
}:
let
  s3Port = 3900;
  rpcPort = 3901;
  webPort = 3902;
  # MagicDNS base domain of the headscale tailnet (see ../headscale); guarded
  # so standalone imports (e.g. the garage VM test) still evaluate
  tailnetBaseDomain = if config ? tailnet then config.tailnet.baseDomain else "garage.local";
in
{
  services.garage = {
    enable = true;
    package = pkgs.garage;

    settings = {
      # single-node cluster on wranHearst
      replication_factor = 1;
      rpc_bind_addr = "[::]:${toString rpcPort}";
      s3_api = {
        s3_region = "garage";
        api_bind_addr = "[::]:${toString s3Port}";
      };
      s3_web = {
        bind_addr = "[::]:${toString webPort}";
        # virtual-host routing key for website buckets
        # (<bucket>.<root_domain>); reaching wranHearst itself goes via
        # MagicDNS (wranHearst.${tailnetBaseDomain}, see ../headscale).
        # per-bucket vhost names would need extra DNS records in the tailnet
        # config; the S3 API below is always available path-agnostically.
        root_domain = ".garage.${tailnetBaseDomain}";
        index = "index.html";
      };
      admin = {
        # the admin API stays on loopback: only local administration is needed
        api_bind_addr = "127.0.0.1:3903";
      };
    };

    # secrets (GARAGE_RPC_SECRET / GARAGE_ADMIN_TOKEN) are managed with
    # sops-nix (see the sops declarations below) and rendered into an
    # environment file; garage refuses to start without an rpc secret and
    # garage 1.x disables the admin API unless an admin token is configured.
    # the `garage` admin wrapper installed by the upstream nixos module
    # sources this file too, so CLI administration works out of the box.
    environmentFile = config.sops.templates."garage-env".path;
  };

  # garage secrets, decrypted from the host's sops file (same pattern as
  # ../wranHearst/sops.nix). the following keys must exist in
  # /etc/kierLeapMount/secrets.yaml as a nested yaml mapping (the file is
  # added imperatively; it is not part of the repo; sops-nix splits secret
  # names on "/" into nested keys):
  #   garage:
  #     rpc-secret:   32 random bytes in hex (garage 1.x requirement),
  #                   e.g. `head -c 32 /dev/urandom | od -An -tx1 | tr -d " \n"`
  #     admin-token:  any random token, e.g. `head -c 32 /dev/urandom | base64`
  # the secrets are rendered into a single environment file because garage's
  # upstream module takes exactly one environmentFile (and the CLI wrapper
  # sources that same file). sops-nix restarts garage (and its dependents)
  # whenever the secrets are re-rendered (e.g. on a rotation at nixos-rebuild)
  sops.secrets."garage/rpc-secret" = {
    sopsFile = "/etc/kierLeapMount/secrets.yaml";
    mode = "0400";
    restartUnits = [ "garage.service" "garage-layout.service" ];
  };
  sops.secrets."garage/admin-token" = {
    sopsFile = "/etc/kierLeapMount/secrets.yaml";
    mode = "0400";
    restartUnits = [ "garage.service" "garage-layout.service" ];
  };
  sops.templates."garage-env" = {
    mode = "0400";
    restartUnits = [ "garage.service" ];
    content = ''
      GARAGE_RPC_SECRET=${config.sops.placeholder."garage/rpc-secret"}
      GARAGE_ADMIN_TOKEN=${config.sops.placeholder."garage/admin-token"}
    '';
  };

  systemd.services.garage = {
    # sops-nix decrypts the secrets at boot: on wranHearst that happens in the
    # sops-install-secrets.service unit (useSystemdActivation is set in
    # ../security); on hosts where sops-nix runs as a plain activation script
    # the unit does not exist and this ordering is a harmless no-op
    after = [ "sops-install-secrets.service" ];
  };

  # a garage node without a layout role cannot serve requests; assign this
  # node a role (and commit the layout) on first start so the cluster is
  # usable immediately. garage layout show stays unassigned until the layout
  # is applied, which makes this check idempotent.
  systemd.services.garage-layout = {
    description = "assign the garage node a single-node cluster layout";
    after = [ "garage.service" ];
    wants = [ "garage.service" ];
    wantedBy = [ "multi-user.target" ];
    path = with pkgs; [
      garage
      curl
      gnugrep
      gawk
      coreutils
    ];
    script = ''
      # the raw garage binary is used here (not the `garage` wrapper from
      # environment.systemPackages), so the rpc secret has to be sourced
      # explicitly from the sops-rendered environment file (with set -a so
      # the variables are exported to the garage child process), otherwise
      # the CLI fails with "No RPC secret provided"
      set -a
      . ${config.sops.templates."garage-env".path}
      set +a
      # wait for the (public) garage health endpoint to come up
      for _ in $(seq 1 30); do
        curl -sf http://127.0.0.1:3903/health > /dev/null && break
        sleep 1
      done
      if garage layout show | grep -q "No nodes currently have a role"; then
        nodeid=$(garage status | grep -E '^[0-9a-f]{16}' | head -1 | awk '{print $1}')
        # NB: the node ids must come before the flags: `--tag` is a
        # multi-value option and would swallow a trailing node id
        garage layout assign "$nodeid" -z dc1 -c 1G -t wranHearst
        garage layout apply --version 1
      fi
    '';
  };

  # wranHearst runs impermanence (root is wiped on reboot), so the garage
  # state must be persisted explicitly. the upstream module uses
  # DynamicUser=true, so the real state directory is /var/lib/private/garage
  # (systemd creates /var/lib/garage as a symlink at service start); bind
  # mounting the public path instead would break the StateDirectory setup
  environment.persistence."/persist".directories = [
    { directory = "/var/lib/private"; mode = "0700"; }
    { directory = "/var/lib/private/garage"; mode = "0700"; }
  ];

  # the S3 API and the web gateway are reachable from the LAN (rpc stays
  # local since this is a single-node cluster; admin API is loopback-only)
  networking.firewall.allowedTCPPorts = [
    s3Port
    webPort
  ];

  # the store is reachable over the headscale tailnet (see ../headscale) at
  # wranHearst.${tailnetBaseDomain}: the agent hosts
  # lanchamarcou / augtibcalcla are enrolled into the tailnet and resolve the
  # host via MagicDNS instead of the old mDNS name wranHearst.local
  # (same pattern as ../postgresql, ../forgejo, ../harmonia)
}
