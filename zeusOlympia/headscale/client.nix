# tailscale client enrollment, used by every host that is not the headscale
# coordination server (i.e. augtibcalcla and lanchamarcou). after enrollment
# the host is part of the tailnet and can discover and reach wranHearst's
# services via MagicDNS (wranHearst.<baseDomain>) - this replaces the old
# Avahi/mDNS-based discovery (wranHearst.local).
#
# enrollment is idempotent: a stamp file written after a successful
# `tailscale up` makes later runs no-ops. for the very first enrollment the
# host needs a reusable preauth key
# at tailnet.authKeyFile (maintained on wranHearst, see ./server.nix); the
# operator copies it there imperatively and then runs
#   systemctl restart headscale-enroll
# mirroring how /etc/kierLeapMount/secrets.yaml is provisioned imperatively.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.tailnet;
  isServer = config.networking.hostName == cfg.serverHostName;
in
{
  config = lib.mkIf (!isServer) {
    services.tailscale = {
      enable = true;
      # accept incoming wireguard traffic over the LAN (direct connections,
      # no DERP relay needed between the tailnet members on the same LAN)
      openFirewall = true;
    };

    # the hosts run impermanence (root is wiped on reboot), so the tailscale
    # node identity/state must be persisted explicitly (same pattern as
    # ../garage, ../openBao, ../vaultWarden, ../kubernetes)
    environment.persistence."/persist".directories = [
      "/var/lib/tailscale"
    ];

    systemd.services.headscale-enroll = {
      description = "enroll this host into the headscale tailnet";
      wantedBy = [ "multi-user.target" ];
      after = [
        "tailscale.service"
        "network-online.target"
      ];
      wants = [
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
      path = [ config.services.tailscale.package pkgs.coreutils ];
      script = ''
        if [ ! -s ${cfg.authKeyFile} ]; then
          echo "no preauth key at ${cfg.authKeyFile}; skipping enrollment"
          echo "(copy the key from /var/lib/headscale/preauth-key on ${cfg.serverHostName} and run: systemctl restart headscale-enroll)"
          exit 0
        fi
        tailscale up \
          --login-server=${cfg.serverUrl} \
          --authkey="$(cat ${cfg.authKeyFile})"
        touch /var/lib/tailscale/.headscale-enrolled
      '';
    };
  };
}
