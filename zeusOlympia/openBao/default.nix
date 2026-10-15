{
  lib,
  pkgs,
  config,
  ...
}:
let
  openBaoPort = 8200;

  # Master switch for the whole openbao module (same pattern as
  # media.enable / tailnet.enable / kubernetes.enable): every declaration
  # below is gated with `lib.mkIf cfg.enable`, so setting
  # `openbao.enable = false;` (the default) disables the module entirely even
  # when it is imported — no service, no firewall ports and no impermanence
  # entries.
  cfg = config.openbao;
in
{
  options.openbao.enable = lib.mkEnableOption "the openbao secrets server";

  config = lib.mkIf cfg.enable {
  services.openbao = {
    enable = true;
    package = pkgs.openbao;

    settings = {
      ui = true;

      # single-node raft storage in the systemd StateDirectory
      # (/var/lib/openbao, provisioned by the nixos module)
      storage.raft = {
        path = "/var/lib/openbao";
        node_id = "wranHearst";
      };

      # reachable from the LAN; TLS is disabled for now because there is no
      # PKI on this network to issue a certificate that other hosts trust
      listener.default = {
        type = "tcp";
        address = "0.0.0.0:${toString openBaoPort}";
        tls_disable = 1;
      };

      # advertised API/cluster addresses: tailnet clients (augtibcalcla,
      # lanchamarcou) resolve wranHearst via MagicDNS (see ../headscale); the
      # old mDNS name wranHearst.local is no longer used anywhere
      api_addr = "http://${config.tailnet.magicFqdn}:${toString openBaoPort}";
      cluster_addr = "http://${config.tailnet.magicFqdn}:8201";
    };
  };

  # the openbao state (raft storage, keys) must be persisted explicitly. the
  # upstream module uses DynamicUser=true, so the real state directory is
  # /var/lib/private/openbao (systemd creates /var/lib/openbao as a symlink
  # at service start); bind mounting the public path instead would break the
  # StateDirectory setup
  environment.persistence."/persist".directories = [
    "/var/lib/private/openbao"
  ];

  networking.firewall = {
    allowedTCPPorts = [
      openBaoPort # client API
      8201 # raft cluster traffic
    ];
  };

  # openbao is reachable over the headscale tailnet (see ../headscale) as
  # wranHearst.tailnet.internal; the old mDNS (_openbao._tcp via
  # services.avahi) advertisement was removed
  };
}
