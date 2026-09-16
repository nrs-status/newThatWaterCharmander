# VM test for the headscale module set (see ../../zeusOlympia/headscale).
#
# Boots a three-node network mirroring the real setup: wranHearst runs the
# headscale coordination server and enrolls a tailscale node into its own
# tailnet (headscale-self-enroll.service); augtibcalcla and lanchamarcou are
# remote clients that enroll with a preauth key (headscale-enroll.service)
# and then discover and reach wranHearst's services via MagicDNS. the
# harmonia binary cache (see ../../zeusOlympia/harmonia) is used as a
# representative wranHearst service to prove availability over the tailnet.
#
# run with: nix build .#checks.x86_64-linux.headscale-vm-test
{
  pkgsLib,
  nixpkgsFlake,
  impermanenceFlake,
}:
let
  pkgs = import nixpkgsFlake { system = "x86_64-linux"; };

  vmResources = {
    virtualisation = {
      memorySize = 2048;
      diskSize = 8192;
      cores = 2;
    };
  };
in
pkgs.testers.runNixOSTest {
  name = "headscale-tailnet";

  nodes = {
    wranHearst =
      { config, ... }:
      {
        imports = [
          impermanenceFlake.nixosModules.impermanence
          ../../zeusOlympia/headscale
          ../../zeusOlympia/harmonia # representative wranHearst service
        ];
        networking.hostName = "wranHearst";
        # clients enroll via this URL before they have MagicDNS; in the real
        # LAN the default is the router-DNS name (wranHearst.home)
        tailnet.serverUrl = "http://${config.networking.primaryIPAddress}:8080";
      } // vmResources;

    augtibcalcla =
      { nodes, config, ... }:
      {
        imports = [
          impermanenceFlake.nixosModules.impermanence
          ../../zeusOlympia/headscale
        ];
        networking.hostName = "augtibcalcla";
        tailnet.serverUrl = "http://${nodes.wranHearst.networking.primaryIPAddress}:8080";
      } // vmResources;

    lanchamarcou =
      { nodes, config, ... }:
      {
        imports = [
          impermanenceFlake.nixosModules.impermanence
          ../../zeusOlympia/headscale
        ];
        networking.hostName = "lanchamarcou";
        tailnet.serverUrl = "http://${nodes.wranHearst.networking.primaryIPAddress}:8080";
      } // vmResources;
  };

  testScript = ''
    import shlex

    start_all()

    # --- the coordination server comes up ---------------------------------
    wranHearst.wait_for_unit("headscale.service")
    wranHearst.wait_for_file("/var/lib/headscale/preauth-key")
    wranHearst.succeed("test -s /var/lib/headscale/preauth-key")
    wranHearst.wait_for_unit("headscale-self-enroll.service")

    # wranHearst is enrolled into its own tailnet
    wranHearst.wait_until_succeeds("tailscale status | grep -q wranHearst")
    wranHearst.wait_until_succeeds(
        "headscale nodes list 2>/dev/null | grep -q wranHearst"
    )

    # --- avahi must be gone -------------------------------------------------
    wranHearst.fail("systemctl cat avahi-daemon.service")
    for client in (augtibcalcla, lanchamarcou):
        client.fail("systemctl cat avahi-daemon.service")

    # --- clients enroll with the preauth key --------------------------------
    key = wranHearst.succeed("cat /var/lib/headscale/preauth-key").strip()
    for client in (augtibcalcla, lanchamarcou):
        client.execute(
            "mkdir -p /etc/kierLeapMount && printf %s "
            + shlex.quote(key)
            + " > /etc/kierLeapMount/headscale-preauth-key"
        )
        client.succeed("systemctl restart headscale-enroll")
        client.wait_until_succeeds("tailscale status | grep -q wranHearst")

    # both clients are registered in the tailnet
    wranHearst.wait_until_succeeds(
        "headscale nodes list 2>/dev/null | grep -q augtibcalcla"
    )
    wranHearst.wait_until_succeeds(
        "headscale nodes list 2>/dev/null | grep -q lanchamarcou"
    )

    # --- discoverability via MagicDNS ---------------------------------------
    for client in (augtibcalcla, lanchamarcou):
        client.wait_until_succeeds(
            "getent hosts wranHearst.tailnet.internal"
        )

    # --- availability of a wranHearst service over the tailnet --------------
    # harmonia (the binary cache, port 5000) answers on its MagicDNS name;
    # retried because the first wireguard handshake can take a few seconds
    for client in (augtibcalcla, lanchamarcou):
        client.wait_until_succeeds(
            "curl -sf http://wranHearst.tailnet.internal:5000/nix-cache-info"
        )
  '';
}
