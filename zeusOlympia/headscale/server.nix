# headscale coordination server, run on wranHearst (see ./tailnet.nix for the
# naming scheme). wranHearst itself also enrolls a tailscale node in its own
# tailnet so that its services (forgejo, garage, harmonia, openBao,
# vaultwarden, postgresql, k3s, ...) become reachable over the tailnet at
# wranHearst.<baseDomain>: this is what replaces the old Avahi/mDNS
# availability and discoverability for augtibcalcla and lanchamarcou.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.tailnet;
  isServer = config.networking.hostName == cfg.serverHostName;

  # headscale CLI invocation: the nixos module installs /etc/headscale/config.yaml
  # with the unix socket location, so the CLI only needs the socket to exist
  headscaleCli = lib.getExe config.services.headscale.package;
  jq = lib.getExe pkgs.jq;

  # headscale 0.29's `preauthkeys create --user` takes a numeric user id, not
  # the user name: resolve it from `users list --output json` (a top-level
  # array), creating the user first if necessary
  ensureUser = ''
    listUid() {
      ${headscaleCli} users list --output json \
        | ${jq} -r '(.users? // . // [])[] | select(.name == "${cfg.user}") | .id'
    }
    uid=$(listUid)
    if [ -z "$uid" ]; then
      # tolerate a concurrent creator (self-enroll and the preauth key unit
      # may run together): ignore the UNIQUE failure and re-resolve the id
      ${headscaleCli} users create ${cfg.user} >/dev/null 2>&1 || true
      uid=$(listUid)
    fi
    test -n "$uid"
  '';

  # `preauthkeys create --output json` prints a single JSON object
  # ({...,"key":"..."}), so the key is extracted with jq
  parseKey = ''${jq} -r .key'';
in
{
  config = lib.mkIf isServer {
    services.headscale = {
      enable = true;

      # listen on all interfaces so LAN clients (not yet enrolled, i.e. not
      # using MagicDNS) can reach the control plane
      address = "0.0.0.0";
      port = cfg.controlPort;

      settings = {
        # advertised control URL: clients keep using it after enrollment, so
        # it must be reachable over the LAN (router DNS name, NOT an mDNS
        # name; see the note on tailnet.serverUrl in ./tailnet.nix). the
        # self-enrolled local node below uses the loopback URL directly.
        server_url = cfg.serverUrl;

        # the server's Noise (control protocol) private key and the embedded
        # DERP server's private key are secrets: they are provisioned with
        # sops-nix from /etc/kierLeapMount/secrets.yaml instead of being
        # generated (and persisted) by headscale itself (see the sops
        # declarations below). generating them on the operator side makes the
        # server identity reproducible and keeps all private material in the
        # sops file.
        noise.private_key_path = config.sops.secrets."headscale/noise-private-key".path;

        dns = {
          magic_dns = true;
          base_domain = cfg.baseDomain;
          # keep the clients' own (router) DNS servers: MagicDNS is then
          # deployed as split DNS for <baseDomain> only, so LAN name
          # resolution (e.g. wranHearst.home) keeps working unchanged
          override_local_dns = false;
        };

        # embedded DERP relay server: headscale refuses to start with an
        # empty DERP map, and no third-party DERP map is reachable on a
        # LAN-only network (the default map is fetched from
        # controlplane.tailscale.com). it also provides a STUN endpoint.
        # NOTE: headscale serves the embedded DERP over the plain-HTTP
        # control listener (this network has no PKI for TLS), so tailscale
        # clients log `tls: first record does not look like a TLS handshake`
        # when they try to use it as a relay; on this private LAN all tailnet
        # members connect directly over wireguard, so the DERP relay is only
        # a fallback that is not actually needed.
        derp = {
          urls = [ ]; # no third-party DERP maps (privacy; works offline)
          auto_update_enabled = false;
          server = {
            enabled = true;
            region_id = 999;
            region_code = "wran";
            region_name = "wranHearst embedded DERP";
            stun_listen_addr = "0.0.0.0:3478";
            # sops-provisioned (see the declarations below); headscale refuses
            # to start the embedded DERP server without a private key
            private_key_path = config.sops.secrets."headscale/derp-private-key".path;
          };
        };
      };
    };

    # the headscale server identity is managed with sops-nix (same pattern as
    # ../garage and ../vaultWarden). the following keys must exist in
    # /etc/kierLeapMount/secrets.yaml as a nested yaml mapping (the file is
    # added imperatively; it is not part of the repo; sops-nix splits secret
    # names on "/" into nested keys):
    #   headscale:
    #     noise-private-key:  the Noise control-protocol private key, in
    #                         headscale's `privkey:<64 hex>` format, e.g. the
    #                         output of `headscale generate private-key`
    #     derp-private-key:   the embedded DERP server private key, same
    #                         format (a second, different
    #                         `headscale generate private-key`)
    # headscale runs as the unprivileged `headscale` user, so the secrets are
    # owned by that user; sops-nix restarts headscale whenever either key is
    # re-rendered (e.g. on a rotation at nixos-rebuild)
    sops.secrets."headscale/noise-private-key" = {
      sopsFile = "/etc/kierLeapMount/secrets.yaml";
      owner = config.services.headscale.user;
      mode = "0400";
      restartUnits = [ "headscale.service" ];
    };
    sops.secrets."headscale/derp-private-key" = {
      sopsFile = "/etc/kierLeapMount/secrets.yaml";
      owner = config.services.headscale.user;
      mode = "0400";
      restartUnits = [ "headscale.service" ];
    };

    # sops-nix decrypts the secrets at boot: on wranHearst that happens in the
    # sops-install-secrets.service unit (useSystemdActivation is set in
    # ../security); on hosts where sops-nix runs as a plain activation script
    # the unit does not exist and this ordering is a harmless no-op
    systemd.services.headscale.after = [ "sops-install-secrets.service" ];

    # the control plane must be reachable from the LAN (enrollment, ongoing
    # control traffic of the enrolled nodes) and the embedded DERP server
    # needs its STUN port (see the derp.server settings above)
    networking.firewall.allowedTCPPorts = [ cfg.controlPort ];
    networking.firewall.allowedUDPPorts = [ 3478 ];

    # wranHearst runs impermanence (root is wiped on reboot), so the headscale
    # state (sqlite db and the reusable preauth key registered in it) must be
    # persisted explicitly; the noise/derp private keys are no longer kept
    # here (they come from sops-nix, see above). declared here, inside the
    # service module (same pattern as ../garage, ../openBao, ../vaultWarden,
    # ../kubernetes)
    environment.persistence."/persist".directories = [
      "/var/lib/headscale"
      "/var/lib/tailscale"
    ];

    # tailscale node co-located with the coordination server: this is what
    # puts wranHearst's services ON the tailnet
    services.tailscale = {
      enable = true;
      # accept incoming wireguard traffic over the LAN
      openFirewall = true;
    };

    # maintain a reusable enrollment (preauth) key so the operator can enroll
    # remote hosts: it is created for the tailnet user, refreshed daily
    # (expiration is 48h, so a valid key always exists) and written to
    # /var/lib/headscale/preauth-key; the operator copies it into
    # ${cfg.authKeyFile} on the client hosts (see ./client.nix).
    #
    # NOTE: unlike the server's Noise/DERP private keys above, this key is
    # deliberately NOT provisioned through sops-nix and is kept refreshed
    # here. headscale only accepts preauth keys that are registered in its
    # database, so a key cannot be generated externally and imported; it has
    # to be created by this server. Rotating it (daily, with a 48h expiry)
    # bounds the lifetime of the credential. A preauth key is a bearer token:
    # anyone who can read it (e.g. from a leaked copy on a client, a backup,
    # or this file) can enroll arbitrary nodes into the tailnet. A key that
    # were created once and never refreshed (in particular a non-expiring one)
    # would therefore grant an attacker permanent, unrevocable access to
    # enroll machines into the tailnet long after the leak; the daily
    # rotation invalidates any leaked copy within at most 48 hours and forces
    # the operator to re-copy the current key.
    systemd.services.headscale-preauth-key = {
      description = "maintain a reusable headscale enrollment (preauth) key";
      wantedBy = [ "multi-user.target" ];
      after = [ "headscale.service" ];
      requires = [ "headscale.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = config.services.headscale.user;
        Group = config.services.headscale.group;
        UMask = "0077";
      };
      path = [ pkgs.jq ];
      script = ''
        ${ensureUser}
        key=$(${headscaleCli} preauthkeys create \
          --user "$uid" --reusable --expiration 48h --output json \
          | ${parseKey})
        test -n "$key"
        printf '%s' "$key" > /var/lib/headscale/preauth-key
        chmod 0600 /var/lib/headscale/preauth-key
      '';
    };

    systemd.timers.headscale-preauth-key = {
      description = "refresh the reusable headscale preauth key daily";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "24h";
        Persistent = true;
      };
    };

    # enroll wranHearst itself into its own tailnet (single-use key generated
    # on the fly, no operator interaction needed). skipped once the tailscale
    # node state exists (ConditionPathExists), so no key is consumed on
    # reboot of an already-registered node.
    systemd.services.headscale-self-enroll = {
      description = "enroll this host's tailscale node into its own headscale tailnet";
      wantedBy = [ "multi-user.target" ];
      after = [
        "headscale.service"
        "headscale-preauth-key.service"
        "tailscale.service"
        "network-online.target"
      ];
      wants = [
        "headscale.service"
        "tailscale.service"
        "network-online.target"
      ];
      # only for the initial enrollment of a virgin node; the stamp file is
      # written below after a successful `tailscale up` (tailscaled.state
      # itself cannot be used: tailscaled creates it at every startup)
      unitConfig.ConditionPathExists = "!/var/lib/tailscale/.headscale-enrolled";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        StateDirectory = "tailscale";
      };
      path = [
        config.services.tailscale.package
        pkgs.coreutils
        pkgs.jq
      ];
      script = ''
        ${ensureUser}
        key=$(${headscaleCli} preauthkeys create \
          --user "$uid" --expiration 1h --output json \
          | ${parseKey})
        test -n "$key"
        # loopback: the coordination server is local; the enrolled node keeps
        # using tailnet.serverUrl for subsequent control connections
        tailscale up \
          --login-server=http://127.0.0.1:${toString cfg.controlPort} \
          --authkey="$key"
        touch /var/lib/tailscale/.headscale-enrolled
      '';
    };
  };
}
