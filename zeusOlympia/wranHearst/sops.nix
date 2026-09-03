{
  pkgsLib,
  frontArmToPlane,
  sopsFlake,
  ...
}:
# the general idea for handling secrets is as follows:
# 1. the secrets are a nix package somewhere and get pulled and set as `defaultSopsFile` (it is possible to do a per-secret configuration that doesn't require setting `defaultSopsFile`
# 2. *the host must manage which users get access to which secret!* this is done locally and is a host-specific configuration
{
  imports = [ sopsFlake.nixosModules.sops ];
  sops = {
    defaultSopsFile = "${frontArmToPlane.packages.x86_64-linux.secrets}/secrets.yaml";
    sops = {
      age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
      secrets = {
        OPENROUTER_API_KEY = {
          owner = "sieyes";
          mode = "0400";
        };
        GITHUB_API_KEY = {
          owner = "sieyes";
          mode = "0400";
        };
      };
    };

  };
}
