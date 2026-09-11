{
  networking = {
    networkmanager = {
      enable = true;
      # declarative fallback wifi profile: the `NetworkManager-ensure-profiles`
      # oneshot rewrites it under /run/NetworkManager/system-connections on
      # every boot and reloads NM, so the machine can always reach the home
      # wifi even if the persisted profile store under
      # /etc/NetworkManager/system-connections is empty or lost (observed
      # failure: full boot to multi-user with sshd listening, but no IP ever
      # assigned). User-created profiles in the persisted store are untouched:
      # ensure-profiles only adds the declared ones.
      # The psk is injected from an environment file instead of being inlined
      # so that no wifi secret lives in this repository.
      ensureProfiles = {
        environmentFiles = [ "/persist/secrets/wifi-psk.env" ];
        profiles = {
          VIRGIN870 = {
            connection = {
              id = "VIRGIN870";
              type = "wifi";
              interface-name = "wlo1";
            };
            wifi = {
              mode = "infrastructure";
              ssid = "VIRGIN870";
            };
            wifi-security = {
              auth-alg = "open";
              key-mgmt = "wpa-psk";
              psk = "$VIRGIN870_PSK";
            };
            ipv4.method = "auto";
            ipv6.method = "auto";
          };
        };
      };
    };
    hostName = "lanchamarcou";
    #DHCP is handled by NetworkManager; setting useDHCP here conflicts with
    #the value NetworkManager's module assigns to it
    useDHCP = false;
  };
}
