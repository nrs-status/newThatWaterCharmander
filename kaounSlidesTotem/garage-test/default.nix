# VM test for the garage module (see ../../zeusOlympia/garage/default.nix).
#
# the real secrets live in the imperatively provisioned sops file
# /etc/kierLeapMount/secrets.yaml, which is not available at build time. this
# test therefore provisions artificial secrets: it generates a throwaway age
# keypair, sops-encrypts a secrets.yaml containing the two keys the garage
# module expects (garage/rpc-secret, garage/admin-token), and exposes
#   - the encrypted file at /etc/kierLeapMount/secrets.yaml (standing in for
#     the real host secrets file) and
#   - the private key as sops.age.keyFile (standing in for the host age key
#     derived from the ssh host key, see ../../zeusOlympia/security).
# apart from that the machine configuration mirrors wranHearst's garage
# setup: the garage module (including its impermanence persistence
# declarations) is imported unchanged and must come up fully working.
#
# run with: nix build .#checks.x86_64-linux.garage-vm-test
{
  pkgsLib,
  nixpkgsFlake,
  sopsFlake,
  impermanenceFlake,
}:
let
  pkgs = import nixpkgsFlake { system = "x86_64-linux"; };

  # artificial secrets: throwaway age key + sops-encrypted secrets.yaml with
  # the exact keys the garage module reads from /etc/kierLeapMount/secrets.yaml
  testSecrets = pkgs.runCommand "garage-test-secrets"
    {
      nativeBuildInputs = with pkgs; [
        age
        sops
      ];
    } ''
    export HOME=$PWD
    mkdir -p $out
    # throwaway keypair (private key -> key.txt, recipient -> pub.txt)
    ${pkgs.age}/bin/age-keygen -o key.txt
    ${pkgs.age}/bin/age-keygen -y key.txt > pub.txt
    # same value formats the old garage-rpc-secret.service generated:
    # rpc secret = 32 random bytes in hex, admin token = random base64
    rpc=$(head -c 32 /dev/urandom | od -An -tx1 | tr -d " \n")
    token=$(head -c 32 /dev/urandom | base64 | tr -d "\n")
    printf 'garage:\n  rpc-secret: %s\n  admin-token: %s\n' "$rpc" "$token" > plain.yaml
    SOPS_AGE_RECIPIENTS="$(cat pub.txt)" ${pkgs.sops}/bin/sops -e plain.yaml > $out/secrets.yaml
    cp key.txt $out/key.txt
    chmod 0600 $out/key.txt $out/secrets.yaml
  '';
in
pkgs.testers.runNixOSTest {
  name = "garage-sops-secrets";

  nodes.machine =
    { config, ... }:
    {
      imports = [
        sopsFlake.nixosModules.sops
        impermanenceFlake.nixosModules.impermanence
        ../../zeusOlympia/garage # the garage module under test (declares the sops secrets too)
      ];

      networking.hostName = "garageTestVm";

      # stand-ins for the wranHearst host setup: the encrypted secrets file
      # takes the place of the imperatively added /etc/kierLeapMount/secrets.yaml
      environment.etc."kierLeapMount/secrets.yaml".source = "${testSecrets}/secrets.yaml";
      # the throwaway age key takes the place of the host-derived age key.
      # sops.age.keyFile must be a runtime path (store paths are rejected), so
      # the key is staged into /var/lib by a unit ordered before
      # sops-install-secrets.service; useSystemdActivation mirrors the
      # wranHearst host (see ../../zeusOlympia/security)
      sops = {
        validateSopsFiles = false; # sopsFile is a runtime path, not a store path
        useSystemdActivation = true;
        age.keyFile = "/var/lib/garage-test-sops/key.txt";
      };
      systemd.services.garageTestSopsKey = {
        description = "stage the artificial sops age key for the garage vm test";
        wantedBy = [ "sysinit.target" ];
        before = [ "sops-install-secrets.service" ];
        after = [ "local-fs.target" ];
        unitConfig.DefaultDependencies = false;
        serviceConfig = {
          Type = "oneshot";
          UMask = "0077";
        };
        script = ''
          mkdir -p /var/lib/garage-test-sops
          cp ${testSecrets}/key.txt /var/lib/garage-test-sops/key.txt
          chmod 0600 /var/lib/garage-test-sops/key.txt
        '';
      };

      virtualisation = {
        graphics = false;
        memorySize = 2048;
      };
    };

  testScript = ''
    machine.wait_for_unit("garage.service")

    # the sops-rendered environment file must exist and contain both variables
    machine.succeed("test -s /run/secrets/rendered/garage-env")
    machine.succeed("grep -q '^GARAGE_RPC_SECRET=.\+' /run/secrets/rendered/garage-env")
    machine.succeed("grep -q '^GARAGE_ADMIN_TOKEN=.\+' /run/secrets/rendered/garage-env")
    # the raw decrypted secrets must exist too
    machine.succeed("test -s /run/secrets/garage/rpc-secret")
    machine.succeed("test -s /run/secrets/garage/admin-token")

    # layout service assigns the single-node role on first boot
    machine.wait_for_unit("garage-layout.service")
    machine.succeed("curl -sf http://127.0.0.1:3903/health")

    # the admin API requires the token from the sops-rendered env file (a
    # request without a valid token is answered with 403, which fails curl -f)
    machine.wait_until_succeeds(
      ". /run/secrets/rendered/garage-env && "
      + 'curl -sf -H "Authorization: Bearer $GARAGE_ADMIN_TOKEN" '
      + "http://127.0.0.1:3903/v1/status -o /dev/null"
    )

    # the CLI wrapper sources the sops-rendered environment file, so
    # administration works without extra configuration (the tag is only
    # shown by layout show, not by status); retried because the garage CLI
    # can transiently fail while the layout ring is still propagating
    machine.wait_until_succeeds("garage status 2>/dev/null | grep -q 'HEALTHY NODES'")
    machine.wait_until_succeeds("garage layout show 2>/dev/null | grep -q wranHearst")

    # exercise the S3 API through the CLI (and through it, the admin token)
    machine.wait_until_succeeds("garage bucket create test-bucket 2>/dev/null")
    machine.wait_until_succeeds("garage bucket list 2>/dev/null | grep -q test-bucket")

    # the S3 API answers on its port (403 = anonymous request rejected, i.e.
    # the API is up and requiring credentials)
    machine.succeed(
      "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3900/ | grep -qE '^4'"
    )
  '';
}
