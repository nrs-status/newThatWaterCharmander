# Headscale: an open-source, self-hosted coordination (control) server for
# Tailscale. This module set replaces the mDNS/Avahi-based availability and
# discoverability of wranHearst's services for the agent hosts augtibcalcla
# and lanchamarcou: every host of this repo enrolls in the tailnet coordinated
# by the headscale server running on wranHearst and reaches the services via
# MagicDNS names (see ./tailnet.nix for the naming scheme).
#
# Layout (imported via zeusOlympia/headscale/default.nix, i.e. by every host
# that adds "./headscale" to its module list):
#   - ./tailnet.nix  shared options (tailnet.*, no host-specific behaviour)
#   - ./server.nix   headscale server + local node enrollment (wranHearst only);
#                    reads the server's Noise/DERP private keys from sops-nix
#   - ./client.nix   tailscale client enrollment (all other hosts)
#
# The server's Noise/DERP private keys are provisioned through sops-nix from
# the host's /etc/kierLeapMount/secrets.yaml (see the sops declarations in
# ./server.nix), so nothing works until the operator adds them by hand. The
# enrollment (preauth) key is deliberately kept out of sops: it has to be
# created by the running server and is rotated automatically (see the note in
# ./server.nix).
{
  imports = [
    ./tailnet.nix
    ./server.nix
    ./client.nix
  ];
}
