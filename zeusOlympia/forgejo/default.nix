{ pkgs, ... }:
let
  forgejoPort = 3000;
in
{
  services.forgejo = {
    enable = true;

    # backed by the local postgresql server (see ../postgresql): the forgejo
    # module registers its own role/database via services.postgresql.ensureUsers
    database.type = "postgres";

    settings = {
      DEFAULT.APP_NAME = "forgejo";
      server = {
        DOMAIN = "wranHearst.local";
        ROOT_URL = "http://wranHearst.local:${toString forgejoPort}/";
        HTTP_ADDR = "0.0.0.0"; # reachable from the LAN
        HTTP_PORT = forgejoPort;
      };
    };
  };

  networking.firewall.allowedTCPPorts = [ forgejoPort ];

  # advertise the forgejo web UI over mDNS so it is discoverable on the
  # LAN as wranHearst.local (publishing itself is configured in ../avahi.nix)
  services.avahi.extraServiceFiles.forgejo = ''
    <?xml version="1.0" standalone='no'?><!--*-nxml-*-->
    <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
    <service-group>
      <name replace-wildcards="yes">%h forgejo</name>
      <service>
        <type>_http._tcp</type>
        <port>${toString forgejoPort}</port>
      </service>
    </service-group>
  '';
}
