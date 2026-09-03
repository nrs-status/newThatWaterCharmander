{
  pkgsLib,
  localLib,
  frontArmToPlane,
  ...
}:
pkgsLib.mkMerge [
  (localLib.mkShellCachingModule frontArmToPlane.devShells.x86_64-linux.sieyes)

  {
    users.users.sieyes = {
      isNormalUser = true;
      extraGroups = [
        "wheel"
        "docker"
        "networkmanager"
        "audio"
        "video"
      ];
    };

    #cache shell
    #secrets management; requires that the host enable to sops module
    sops = {
      secrets = {
        OPENROUTER_API_KEY = {
          owner = "sieyes";
          mode = "0400";
        };
        git.github.nrs-status.apiKey = {
          owner = "sieyes";
          mode = "0400";
        };
        git.github.nrs-status.credential = {
          owner = "sieyes";
          mode = "0400";
        };
        THATWATERCHARMANDER_PATH = {
          owner = "sieyes";
          mode = "0400";
        };
      };

    };

  }
]
