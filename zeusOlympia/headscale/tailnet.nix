# Shared tailnet options. These are pure declarations (no service config), so
# this file is safe to import on every host of the repo; the actual headscale
# server and tailscale client configuration live in ./server.nix and
# ./client.nix, which activate themselves based on networking.hostName.
#
# Naming scheme: with MagicDNS enabled and base_domain = `tailnet.internal`,
# every enrolled node gets the FQDN `<hostname>.tailnet.internal`; wranHearst's
# services are therefore reachable at wranHearst.tailnet.internal:<port> from
# any enrolled host (replacing the old mDNS name wranHearst.local).
#
# Master switch: `tailnet.enable` (default false). When disabled, ./server.nix
# and ./client.nix configure nothing (no headscale, no tailscaled, no
# enrollment units, no firewall ports, no persisted state), and `magicFqdn`
# falls back to the server's router-DNS LAN name
# (`<serverHostName>.<lanDomain>`, e.g. wranHearst.home) so every consumer
# (forgejo, openBao, k3s, telegraf, the nix substituter, ...) keeps a
# resolvable address. Re-enable with `tailnet.enable = true;` (set in
# empTriageCan/heg-twPlant/default.nix for all hosts).
{ config, lib, ... }:
{
  options.tailnet = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to run the headscale tailnet (headscale server on
        serverHostName, tailscale clients everywhere else). When false,
        magicFqdn resolves to the server's LAN name instead of MagicDNS.
      '';
    };

    # router-DNS domain of the LAN (unicast DNS from the router's DHCP
    # leases); used for magicFqdn while the tailnet is disabled
    lanDomain = lib.mkOption {
      type = lib.types.str;
      default = "home";
      description = "LAN (router DNS) domain used when the tailnet is disabled.";
    };

    # host that runs the headscale coordination server
    serverHostName = lib.mkOption {
      type = lib.types.str;
      default = "wranHearst";
      description = "Name of the host running the headscale coordination server.";
    };

    # MagicDNS base domain: node FQDNs are `<hostname>.<baseDomain>`
    baseDomain = lib.mkOption {
      type = lib.types.str;
      default = "tailnet.internal";
      description = ''
        MagicDNS base domain of the tailnet. The FQDN of an enrolled node is
        `<hostname>.<baseDomain>` (e.g. wranHearst.tailnet.internal).
      '';
    };

    # convenience: the name under which the coordination server (wranHearst)
    # is reached: its MagicDNS FQDN when the tailnet is enabled, otherwise
    # its router-DNS LAN name
    magicFqdn = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      description = ''
        FQDN of the coordination server: `<serverHostName>.<baseDomain>`
        (MagicDNS) when tailnet.enable is true, otherwise
        `<serverHostName>.<lanDomain>` (router DNS).
      '';
    };

    # URL remote clients use to reach the coordination server *before* they
    # are enrolled (enrollment cannot use MagicDNS yet, the client is not in
    # the tailnet at that point). the default is the router-DNS name of
    # wranHearst (unicast DNS served from the router's DHCP leases, as used
    # for the harmonia substituter in ../nix.nix) - NOT an mDNS `.local`
    # name; mDNS/Avahi is deliberately no longer used anywhere.
    serverUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://wranHearst.home:8080";
      description = "Coordination server URL used by clients to enroll.";
    };

    # TCP port the headscale HTTP control plane listens on
    controlPort = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "TCP port of the headscale control plane (HTTP).";
    };

    # headscale user (namespace) all nodes of this tailnet are registered in
    user = lib.mkOption {
      type = lib.types.str;
      default = "wran";
      description = "headscale user (namespace) the tailnet nodes belong to.";
    };

    # where remote clients expect the reusable enrollment (preauth) key; the
    # operator copies the key rendered on wranHearst (see ./server.nix, which
    # maintains it in /var/lib/headscale/preauth-key) into this file
    # imperatively, mirroring the /etc/kierLeapMount/secrets.yaml pattern
    authKeyFile = lib.mkOption {
      type = lib.types.str;
      default = "/etc/kierLeapMount/headscale-preauth-key";
      description = ''
        File a remote client reads its enrollment (preauth) key from.
      '';
    };
  };

  config.tailnet.magicFqdn =
    if config.tailnet.enable then
      "${config.tailnet.serverHostName}.${config.tailnet.baseDomain}"
    else
      "${config.tailnet.serverHostName}.${config.tailnet.lanDomain}";
}
