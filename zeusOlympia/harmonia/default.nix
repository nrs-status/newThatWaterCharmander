# harmonia binary cache server: serves the local /nix/store over HTTP so
# the other hosts of this repo (augtibcalcla, lanchamarcou) can use
# wranHearst as a substituter, e.g. to fetch the linux 6.18 kernel binary
# used by the `vm` scripts of the frontArmToPlane input (see
# ../wranHearst/linuxKernel.nix) without building it themselves.
# This module is only imported by the wranHearst host (see ../../empTriageCan).
{
  pkgs,
  pkgsLib,
  ...
}:
{
  services.harmonia = {
    enable = true;
    package = pkgs.harmonia;

    # key generated with `nix-store --generate-binary-cache-key wranHearst-cache
    # cache-key.sec cache-key.pub`; the matching public key is in ./cache-key.pub
    # and is referenced by the client hosts' `nix.settings.trusted-public-keys`.
    # NOTE: the key lives in the nix store, so it is world-readable; the secret
    # should move to sops if this cache ever leaves the private LAN.
    cache.signKeyPaths = [ ./cache-key.sec ];

    cache.settings = {
      bind = "[::]:5000"; # reachable from the LAN
    };
  };

  networking.firewall.allowedTCPPorts = [ 5000 ];

  # advertise the cache over mDNS so it is discoverable on the LAN as
  # wranHearst.local (publishing itself is configured in ../avahi.nix)
  services.avahi.extraServiceFiles.harmonia = ''
    <?xml version="1.0" standalone='no'?><!DOCTYPE service-group SYSTEM "avahi-service.dtd">
    <service-group>
      <name replace-wildcards="yes">nix binary cache on %h</name>
      <service>
        <type>_nix-cache._tcp</type>
        <port>5000</port>
      </service>
    </service-group>
  '';
}