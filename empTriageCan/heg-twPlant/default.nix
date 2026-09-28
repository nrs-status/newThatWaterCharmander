{ localLib, localModules, ... }:
{
  imports = [
    (localLib.mkDirectoryImporterModule ./.)

    localModules.console
    localModules.headscale # tailnet/MagicDNS discovery (self-gating per hostname)
    localModules.bootIntrospection # persistent journald + systemd initrd (required by fs/impermanence rollback)
  ];

  # headscale/tailscale tailnet is DISABLED on all hosts: its IPv6 overlay
  # (fd7a:115c:a1e0::/48) blackholed traffic while peers were offline and the
  # embedded DERP relay (plain HTTP) was unusable. with this off, services are
  # addressed by their router-DNS LAN name (tailnet.magicFqdn ->
  # wranHearst.home). flip to true to re-enable; existing node state under
  # /persist/var/lib/{headscale,tailscale} is left in place for that.
  tailnet.enable = false;
}
