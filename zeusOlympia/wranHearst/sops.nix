{
  frontArmToPlane,
  ...
}:
{

  sops = {
    secrets = {
      "keys/openrouter" = {
        owner = "sieyes";
        mode = "0600";
        sopsFile = "${frontArmToPlane.packages.x86_64-linux.secrets}/secrets.yaml";
      };
      "keys/git/github/nrs-status" = {
        owner = "sieyes";
        mode = "0600";
        sopsFile = "${frontArmToPlane.packages.x86_64-linux.secrets}/secrets.yaml";
      };
      "ssh/sieyes-to-soc7099" = {
        owner = "root";
        mode = "0600";
        sopsFile = "/etc/kierLeapMount/secrets.yaml";
      };
      "ssh/sieyes-to-plat2548" = {
        owner = "root";
        mode = "0600";
        sopsFile = "/etc/kierLeapMount/secrets.yaml";
      };
    };

  };
}
