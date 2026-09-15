{
  pkgs,
  ...
}:
let
  openBaoPort = 8200;
in
{
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

      # advertised API/cluster addresses so LAN clients know where to connect
      api_addr = "http://wranHearst.local:${toString openBaoPort}";
      cluster_addr = "http://wranHearst.local:8201";
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

  # advertise openbao over mDNS (see ../avahi.nix) so LAN clients can
  # discover it as wranHearst.local via e.g. `avahi-browse -r _openbao._tcp`
  services.avahi.extraServiceFiles.openbao = ''
    <?xml version="1.0" standalone='no'?><!DOCTYPE service-group SYSTEM "avahi-service.dtd">
    <service-group>
      <name replace-wildcards="yes">openbao on %h</name>
      <service>
        <type>_openbao._tcp</type>
        <port>${toString openBaoPort}</port>
      </service>
    </service-group>
  '';
}
