{
  pkgs,
  ...
}:
let
  s3Port = 3900;
  rpcPort = 3901;
  webPort = 3902;
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
        # websites are served as <bucket>.garage.local:<webPort>
        root_domain = ".garage.local";
        index = "index.html";
      };
      admin = {
        # the admin API stays on loopback: only local administration is needed
        api_bind_addr = "127.0.0.1:3903";
      };
    };

    # secrets (GARAGE_RPC_SECRET / GARAGE_ADMIN_TOKEN) are provisioned at
    # first boot by garage-rpc-secret.service below; garage refuses to start
    # without an rpc secret and garage 1.x disables the admin API unless an
    # admin token is configured. the `garage` admin wrapper installed by the
    # upstream nixos module sources this file too, so CLI administration
    # works out of the box.
    # NB: the garage unit uses DynamicUser=true (see the upstream module), so
    # its StateDirectory is managed under /var/lib/private/garage (with
    # /var/lib/garage as a symlink created by systemd at start); the secret
    # file must live in the private state directory, otherwise provisioning a
    # public /var/lib/garage makes systemd's StateDirectory migration fail
    # with EBUSY when the directory is an impermanence bind mount
    environmentFile = "/var/lib/private/garage/rpc-secret.env";
  };

  # provision secrets once; skipped on subsequent boots (ConditionPathExists)
  systemd.services.garage-rpc-secret = {
    description = "provision garage rpc secret and admin token";
    unitConfig.ConditionPathExists = "!/var/lib/private/garage/rpc-secret.env";
    serviceConfig = {
      Type = "oneshot";
      UMask = "0077";
    };
    script = ''
      mkdir -p /var/lib/private/garage
      # garage 1.x expects the rpc secret as 32 random bytes in hex
      rpcSecret=$(head -c 32 /dev/urandom | od -An -tx1 | tr -d " \n")
      adminToken=$(head -c 32 /dev/urandom | base64 | tr -d "\n")
      printf "GARAGE_RPC_SECRET=%s\nGARAGE_ADMIN_TOKEN=%s\n" "$rpcSecret" "$adminToken" \
        > /var/lib/private/garage/rpc-secret.env
    '';
  };

  systemd.services.garage = {
    after = [ "garage-rpc-secret.service" ];
    wants = [ "garage-rpc-secret.service" ];
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
      # explicitly (with set -a so the variables are exported to the garage
      # child process), otherwise the CLI fails with "No RPC secret provided"
      set -a
      . /var/lib/private/garage/rpc-secret.env
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

  # advertise the store over mDNS (see ../avahi.nix) so the agent hosts
  # lanchamarcou / augtibcalcla can discover it as wranHearst.local instead
  # of hardcoding addresses (same pattern as ../postgresql and ../forgejo)
  services.avahi.extraServiceFiles.garage = ''
    <?xml version="1.0" standalone='no'?><!--*-nxml-*-->
    <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
    <service-group>
      <name replace-wildcards="yes">garage on %h</name>
      <service>
        <type>_s3._tcp</type>
        <port>${toString s3Port}</port>
        <txt-record>region=garage</txt-record>
      </service>
      <service>
        <type>_http._tcp</type>
        <port>${toString webPort}</port>
        <txt-record>path=/</txt-record>
      </service>
    </service-group>
  '';
}
