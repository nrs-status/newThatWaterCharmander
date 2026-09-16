# harmonia binary cache server: serves the local /nix/store over HTTP so
# the other hosts of this repo (augtibcalcla, lanchamarcou) can use
# wranHearst as a substituter (http://wranHearst.tailnet.internal:5000, see
# ../nix.nix) without building everything themselves.
#
# NOTE on naming: the cache is reachable over the headscale tailnet (see
# ../headscale) as wranHearst.tailnet.internal via MagicDNS. that name is a
# plain DNS name served by the tailscale resolver (100.100.100.100, wired
# into the system resolver), so unlike the old mDNS `.local` name it CAN be
# resolved by nix (nix hardcodes `files dns` NSS lookup, which still goes
# through resolv.conf/systemd-resolved) and is used directly as the
# substituter URL.
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

  # the cache is reachable over the headscale tailnet (see ../headscale) at
  # wranHearst.tailnet.internal; the old mDNS (_nix-cache._tcp via
  # services.avahi) advertisement was removed
}