# VM test for the vaultwarden module (see ../../zeusOlympia/vaultWarden/default.nix).
#
# the real secrets live in the imperatively provisioned sops file
# /etc/kierLeapMount/secrets.yaml, which is not available at build time. this
# test therefore provisions artificial secrets: it generates a throwaway age
# keypair, sops-encrypts a secrets.yaml containing the key the vaultwarden
# module expects (vaultwarden/admin-token), and exposes
#   - the encrypted file at /etc/kierLeapMount/secrets.yaml (standing in for
#     the real host secrets file) and
#   - the private key as sops.age.keyFile (standing in for the host age key
#     derived from the ssh host key, see ../../zeusOlympia/security).
# apart from that the machine configuration mirrors wranHearst's vaultwarden
# setup: the vaultwarden module (including its impermanence persistence
# declarations) is imported unchanged and must come up fully working.
# wranHearst runs postgresql (see ../../zeusOlympia/postgresql), which
# vaultwarden's dbBackend = "postgresql" needs, so a local postgres with the
# vaultwarden database is provisioned here too (the DATABASE_URL must come
# from `config`, which the upstream module renders into a store-path env file
# and is therefore not a secret and not part of the module under test).
#
# run with: nix build .#checks.x86_64-linux.vaultwarden-vm-test
{
  pkgsLib,
  nixpkgsFlake,
  sopsFlake,
  impermanenceFlake,
}:
let
  pkgs = import nixpkgsFlake { system = "x86_64-linux"; };

  # artificial secrets: throwaway age key + sops-encrypted secrets.yaml with
  # the exact key the vaultwarden module reads from /etc/kierLeapMount/secrets.yaml
  testSecrets = pkgs.runCommand "vaultwarden-test-secrets"
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
    # random admin token (same value format the docs suggest:
    # `head -c 32 /dev/urandom | base64`)
    token=$(head -c 32 /dev/urandom | base64 | tr -d "\n")
    printf 'vaultwarden:\n  admin-token: %s\n' "$token" > plain.yaml
    SOPS_AGE_RECIPIENTS="$(cat pub.txt)" ${pkgs.sops}/bin/sops -e plain.yaml > $out/secrets.yaml
    cp key.txt $out/key.txt
    chmod 0600 $out/key.txt $out/secrets.yaml
  '';
in
pkgs.testers.runNixOSTest {
  name = "vaultwarden-sops-secrets";

  nodes.machine =
    { config, ... }:
    {
      imports = [
        sopsFlake.nixosModules.sops
        impermanenceFlake.nixosModules.impermanence
        ../../zeusOlympia/vaultWarden # the vaultwarden module under test (declares the sops secret too)
      ];

      networking.hostName = "vaultwardenTestVm";

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
        age.keyFile = "/var/lib/vaultwarden-test-sops/key.txt";
      };
      systemd.services.vaultwardenTestSopsKey = {
        description = "stage the artificial sops age key for the vaultwarden vm test";
        wantedBy = [ "sysinit.target" ];
        before = [ "sops-install-secrets.service" ];
        after = [ "local-fs.target" ];
        unitConfig.DefaultDependencies = false;
        serviceConfig = {
          Type = "oneshot";
          UMask = "0077";
        };
        script = ''
          mkdir -p /var/lib/vaultwarden-test-sops
          cp ${testSecrets}/key.txt /var/lib/vaultwarden-test-sops/key.txt
          chmod 0600 /var/lib/vaultwarden-test-sops/key.txt
        '';
      };

      # vaultwarden's dbBackend = "postgresql" needs a postgres server (on
      # wranHearst that is provided by ../../zeusOlympia/postgresql)
      services.postgresql = {
        enable = true;
        ensureDatabases = [ "vaultwarden" ];
        ensureUsers = [
          {
            name = "vaultwarden";
            ensureDBOwnership = true;
          }
        ];
      };
      services.vaultwarden.config.DATABASE_URL = "postgresql:///vaultwarden?host=/run/postgresql";

      virtualisation = {
        graphics = false;
        memorySize = 2048;
      };
    };

  testScript = ''
    machine.wait_for_unit("vaultwarden.service")

    # the sops-rendered environment file must exist and contain the token
    machine.succeed("test -s /run/secrets/rendered/vaultwarden-env")
    machine.succeed("grep -q '^ADMIN_TOKEN=.\+' /run/secrets/rendered/vaultwarden-env")
    # the raw decrypted secret must exist too
    machine.succeed("test -s /run/secrets/vaultwarden/admin-token")

    # vaultwarden must be up and answering
    machine.wait_until_succeeds("curl -sf http://127.0.0.1:8222/alive")

    # the admin panel must be enabled through the sops-rendered ADMIN_TOKEN:
    # without it vaultwarden answers 404 on /admin, with it the admin
    # login page (200) is served
    machine.wait_until_succeeds(
      "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8222/admin | grep -q '^200$'"
    )

  '';
}
