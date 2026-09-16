# harmonia binary cache server: serves the local /nix/store over HTTP so
# the other hosts of this repo (augtibcalcla, lanchamarcou) can use
# wranHearst as a substituter (http://wranHearst.home:5000, see ../nix.nix)
# without building everything themselves.
#
# NOTE on naming: the cache is advertised over mDNS below so it is
# discoverable on the LAN as wranHearst.local (publishing itself is
# configured in ../avahi.nix), but the SUBSTITUTER URL must use the
# router-DNS name `wranHearst.home` instead: nix restricts hostname
# resolution to `files dns` (no nscd, no mDNS) to keep sandboxed builds
# hermetic, so it cannot resolve .local names.
# This module is only imported by the wranHearst host (see ../../empTriageCan).
{
  pkgs,
  pkgsLib,
  ...
}:
{
  services.harmonia = {
    # NOTE: must be `cache.enable` (not the deprecated flat `enable`), otherwise
    # every evaluation of this host emits a renamed-option warning
    cache.enable = true;
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