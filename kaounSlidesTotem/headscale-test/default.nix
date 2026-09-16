# VM test for the headscale module set (see ../../zeusOlympia/headscale), whose
# server secrets are now provisioned through sops-nix.
#
# Boots a three-node network mirroring the real setup: wranHearst runs the
# headscale coordination server and enrolls a tailscale node into its own
# tailnet (headscale-self-enroll.service); augtibcalcla and lanchamarcou are
# remote clients that enroll with a preauth key (headscale-enroll.service)
# and then discover and reach wranHearst's services via MagicDNS. the
# harmonia binary cache (see ../../zeusOlympia/harmonia) is used as a
# representative wranHearst service to prove availability over the tailnet.
#
# the real server secrets live in the imperatively provisioned sops file
# /etc/kierLeapMount/secrets.yaml, which is not available at build time. this
# test therefore provisions artificial ones:
#   - a throwaway age keypair is generated inside the wranHearst VM (standing
#     in for the host age key derived from the ssh host key, see
#     ../../zeusOlympia/security);
#   - the two headscale *server* private keys (noise + embedded DERP) are
#     generated inside the VM exactly like the operator would, with
#     `headscale generate private-key`, then sops-encrypted (with the
#     throwaway age key) into /etc/kierLeapMount/secrets.yaml, from where
#     sops-nix decrypts them for headscale;
#   - the *client* enrollment (preauth) key is NOT sops-provisioned (by
#     design: see ../../zeusOlympia/headscale/server.nix). it still has to be
#     registered in headscale's database, which only exists at runtime, so the
#     test starts wranHearst first, reads the reusable key it generated, and
#     copies it into the clients' /etc/kierLeapMount/headscale-preauth-key,
#     mirroring what the operator does by hand.
#
# run with: nix build .#checks.x86_64-linux.headscale-vm-test
{
  pkgsLib,
  nixpkgsFlake,
  sopsFlake,
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
  name = "headscale-sops-secrets";

  nodes = {
    wranHearst =
      { config, ... }:
      {
        imports = [
          sopsFlake.nixosModules.sops
          impermanenceFlake.nixosModules.impermanence
          ../../zeusOlympia/headscale
          ../../zeusOlympia/harmonia # representative wranHearst service
        ];
        networking.hostName = "wranHearst";
        # clients enroll via this URL before they have MagicDNS; in the real
        # LAN the default is the router-DNS name (wranHearst.home)
        tailnet.serverUrl = "http://${config.networking.primaryIPAddress}:8080";

        # sops stand-ins for the host setup (see ../../zeusOlympia/security):
        # the throwaway age key takes the place of the host-derived age key and
        # the encrypted secrets file takes the place of the imperatively added
        # /etc/kierLeapMount/secrets.yaml. sops.age.keyFile must be a runtime
        # path (store paths are rejected) and useSystemdActivation mirrors the
        # wranHearst host, so the secrets are decrypted by
        # sops-install-secrets.service at boot.
        sops = {
          validateSopsFiles = false; # sopsFile is a runtime path, not a store path
          useSystemdActivation = true;
          age.keyFile = "/var/lib/headscale-test-sops/key.txt";
        };

        # generate the throwaway age key and the two headscale server private
        # keys inside the VM, then sops-encrypt the server keys into
        # /etc/kierLeapMount/secrets.yaml. this must run before
        # sops-install-secrets.service (which decrypts the file) and after
        # local-fs.target (so /var/lib and /etc are writable)
        systemd.services.headscaleTestSopsSecrets = {
          description = "generate the artificial headscale server secrets and sops age key";
          wantedBy = [ "sysinit.target" ];
          before = [ "sops-install-secrets.service" ];
          after = [ "local-fs.target" ];
          unitConfig.DefaultDependencies = false;
          path = with pkgs; [
            age
            sops
            headscale
            coreutils
          ];
          serviceConfig = {
            Type = "oneshot";
            UMask = "0077";
          };
          script = ''
            mkdir -p /var/lib/headscale-test-sops /etc/kierLeapMount
            if [ ! -s /var/lib/headscale-test-sops/key.txt ]; then
              age-keygen -o /var/lib/headscale-test-sops/key.txt
            fi
            chmod 0600 /var/lib/headscale-test-sops/key.txt

            # only generate the encrypted file once (it is consumed by
            # sops-install-secrets and must stay in sync with the age key)
            if [ ! -s /etc/kierLeapMount/secrets.yaml ]; then
              recipient=$(age-keygen -y /var/lib/headscale-test-sops/key.txt)
              # headscale's `generate private-key` prints `privkey:<64 hex>`,
              # exactly the format headscale's own readOrCreatePrivateKey
              # writes to disk and expects to read back
              noise=$(headscale generate private-key)
              derp=$(headscale generate private-key)
              printf 'headscale:\n  noise-private-key: %s\n  derp-private-key: %s\n' \
                "$noise" "$derp" > /run/headscale-server-plain.yaml
              SOPS_AGE_RECIPIENTS="$recipient" \
                sops -e /run/headscale-server-plain.yaml \
                > /etc/kierLeapMount/secrets.yaml
              rm -f /run/headscale-server-plain.yaml
              chmod 0600 /etc/kierLeapMount/secrets.yaml
            fi
          '';
        };
      } // vmResources;

    augtibcalcla =
      { nodes, config, ... }:
      {
        imports = [
          sopsFlake.nixosModules.sops
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
          sopsFlake.nixosModules.sops
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

    # --- the coordination server comes up with sops-provisioned keys -------
    wranHearst.wait_for_unit("headscale.service")

    # both server private keys must have been generated in the VM, encrypted
    # into /etc/kierLeapMount/secrets.yaml, decrypted from it by sops-nix and
    # handed to headscale (owned by its unprivileged user). headscale only
    # starts if both are readable, so headscale.service being up already
    # proves it is using them.
    wranHearst.succeed("test -s /run/secrets/headscale/noise-private-key")
    wranHearst.succeed("test -s /run/secrets/headscale/derp-private-key")
    wranHearst.succeed("stat -c '%U' /run/secrets/headscale/noise-private-key | grep -qx headscale")
    wranHearst.succeed("stat -c '%U' /run/secrets/headscale/derp-private-key | grep -qx headscale")
    # the running headscale process must actually use the sops-rendered paths
    # (headscale's own config file is the one passed to `headscale serve`, not
    # the minimal /etc/headscale/config.yaml used by the CLI)
    wranHearst.succeed(
        "pid=$(systemctl show -p MainPID --value headscale); "
        "cfg=$(tr '\\0' '\\n' < /proc/$pid/cmdline | grep -m1 'headscale.yaml'); "
        "grep -q 'private_key_path: /run/secrets/headscale/noise-private-key' \"$cfg\""
    )
    wranHearst.succeed(
        "pid=$(systemctl show -p MainPID --value headscale); "
        "cfg=$(tr '\\0' '\\n' < /proc/$pid/cmdline | grep -m1 'headscale.yaml'); "
        "grep -q 'private_key_path: /run/secrets/headscale/derp-private-key' \"$cfg\""
    )
    # and it must NOT have fallen back to generating (and persisting) its own
    # keys in /var/lib/headscale, which is what the default config would do
    wranHearst.fail("test -e /var/lib/headscale/noise_private.key")
    wranHearst.fail("test -e /var/lib/headscale/derp_server_private.key")

    # the once-only reusable preauth key is created on first boot
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
    # the key is maintained by the (unmodified) preauth-key service on
    # wranHearst and copied here by the test, exactly like the operator copies
    # it into tailnet.authKeyFile by hand
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
