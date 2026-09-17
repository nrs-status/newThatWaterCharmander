{ config, ... }:
let
  # MagicDNS FQDN of wranHearst in the headscale tailnet (see ./headscale);
  # guarded so imports without the tailnet module still evaluate
  magicFqdn = if config ? tailnet then config.tailnet.magicFqdn else "wranHearst.home";
in
{
  nix.settings = {
    substituters = [
        # NOTE: this uses the MagicDNS name of wranHearst in the headscale
        # tailnet. it is a
        # plain DNS name (served by the tailscale resolver wired into the
        # system resolver), so nix CAN resolve it: unlike the old mDNS name
        # wranHearst.local, MagicDNS works through the `files dns` NSS lookup
        # nix hardcodes (the query goes to resolv.conf -> systemd-resolved ->
        # tailscale), so the substituter is not silently skipped. before a
        # host is enrolled into the tailnet the name does not resolve and nix
        # skips the substituter until enrollment, which is harmless.
      "http://${magicFqdn}:5000"
    ];
    trusted-public-keys = [
      "wranHearst-cache:G6wjtR3BPM+c3EZGSI1i4b/j5YM/SvKEMp4bUUyqNEA="
    ];
  };
}
