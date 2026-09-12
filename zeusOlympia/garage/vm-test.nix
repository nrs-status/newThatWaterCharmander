# NixOS VM test for the Garage object store module (zeusOlympia/garage).
#
# Boots a minimal VM running the garage service and verifies end-to-end that
# the object store works:
#   1. the systemd unit starts and the admin API reports a healthy cluster
#   2. a layout with one node can be created and applied
#   3. a bucket + key can be created via the garage CLI
#   4. an object can be uploaded and downloaded through the S3 API (awscli)
#
# Run with: nix build .#checks.x86_64-linux.garage-vm-test
{
  pkgs,
  lib,
  ...
}:
pkgs.testers.nixosTest {
  name = "garage";

  nodes.machine =
    { ... }:
    {
      imports = [
        ./options.nix
        ./server.nix
      ];

      services.garage = {
        enable = true;
        rpcSecretFile = pkgs.writeText "garage-rpc-secret" "a4bf2049e800048c317e8f3e2c17b83d43a1a5e17a67f61a3d1fd83e2f8d6337";
        adminTokenFile = pkgs.writeText "garage-admin-token" "Y9WcxDXQv0dFRoX7L5BGkaGNPNuoRxUP3EobRTwrzjA=";
      };

      environment.systemPackages = with pkgs; [
        awscli2
        jq
      ];
    };

  testScript =
    let
      # single-line env prefix for the garage CLI: it needs the same secret
      # env vars as the daemon; the copies in the unit's private runtime dir
      # are readable by root
      garageCli = "export GARAGE_RPC_SECRET_FILE=/run/garage/rpc-secret GARAGE_ADMIN_TOKEN_FILE=/run/garage/admin-token; garage -c /etc/garage/garage.toml";
    in
    ''
      machine.wait_for_unit("garage.service")

      with subtest("admin API reports a healthy cluster"):
          machine.wait_until_succeeds(
            'curl -sf -H "Authorization: Bearer $(cat /run/garage/admin-token)" http://127.0.0.1:3903/v1/health'
          )
          machine.log(machine.succeed(
            'curl -s -H "Authorization: Bearer $(cat /run/garage/admin-token)" http://127.0.0.1:3903/v1/status'
          ))

      with subtest("cluster layout can be assigned and applied"):
          node_id = machine.succeed(
            'curl -s -H "Authorization: Bearer $(cat /run/garage/admin-token)" '
            "http://127.0.0.1:3903/v1/status | jq -r '.nodes[] | select(.isUp == true) | .id'"
          ).strip()
          machine.log(f"node id: {node_id}")
          machine.succeed("${garageCli} layout assign -z dc1 -c 1G {node_id}".format(node_id=node_id))
          machine.succeed("${garageCli} layout apply --version 1")

      with subtest("bucket and key can be created and an object round-trips through S3"):
          machine.succeed("${garageCli} bucket create test-bucket")
          machine.succeed("${garageCli} key create test-key")
          machine.succeed("${garageCli} bucket allow --read --write --owner test-bucket --key test-key")

          key_info = machine.succeed("${garageCli} key info test-key --show-secret")
          machine.log(key_info)
          access_key = machine.succeed(
            "${garageCli} key info test-key --show-secret | awk '/^Key ID/ {print $3}'"
          ).strip()
          secret_key = machine.succeed(
            "${garageCli} key info test-key --show-secret | awk '/^Secret key/ {print $3}'"
          ).strip()
          assert access_key != "", "could not parse S3 access key id"
          assert secret_key != "", "could not parse S3 secret key"

          machine.succeed("echo garage-rocks > /tmp/obj.txt")
          machine.succeed(
            f"env AWS_ACCESS_KEY_ID={access_key} AWS_SECRET_ACCESS_KEY={secret_key} AWS_DEFAULT_REGION=garage "
            "aws --endpoint-url http://127.0.0.1:3900 s3 cp /tmp/obj.txt s3://test-bucket/obj.txt"
          )
          downloaded = machine.succeed(
            f"env AWS_ACCESS_KEY_ID={access_key} AWS_SECRET_ACCESS_KEY={secret_key} AWS_DEFAULT_REGION=garage "
            "aws --endpoint-url http://127.0.0.1:3900 s3 cp s3://test-bucket/obj.txt -"
          )
          assert "garage-rocks" in downloaded, f"object content mismatch: {downloaded}"
    '';
}
