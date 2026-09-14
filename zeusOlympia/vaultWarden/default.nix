{
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

      # the admin panel is disabled by default (ADMIN_TOKEN unset), which is
      # the safe choice for a LAN-exposed instance
      SIGNUPS_ALLOWED = false; # signups are managed manually by the admin
    };
  };

  # the vaultwarden state must be persisted explicitly
  environment.persistence."/persist".directories = [ "/var/lib/vaultwarden" ];

  networking.firewall.allowedTCPPorts = [ vaultwardenPort ];

  # advertise the vaultwarden API over mDNS (see ../avahi.nix) so the LAN
  # clients can discover it as wranHearst.local
  services.avahi.extraServiceFiles.vaultwarden = ''
    <?xml version="1.0" standalone='no'?><!DOCTYPE service-group SYSTEM "avahi-service.dtd">
    <service-group>
      <name replace-wildcards="yes">vaultwarden on %h</name>
      <service>
        <type>_http._tcp</type>
        <port>${toString vaultwardenPort}</port>
      </service>
    </service-group>
  '';
}
