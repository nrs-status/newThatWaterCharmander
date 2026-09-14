{
  pkgs,
  pkgsLib,
  localLib,
  frontArmToPlane,
  ...
}:
pkgsLib.mkMerge [
  (localLib.mkShellCachingModule {
    inherit pkgs;
    shell = frontArmToPlane.devShells.x86_64-linux.sieyes;
  })

  {
    users.users.sieyes = {
      isNormalUser = true;
      extraGroups = [
        "wheel"
        "docker"
        "networkmanager"
        "audio"
        "video"
        "keyd"
      ];
    };

    #cache shell
    #secrets management; requires that the host enable to sops module
    sops = {
      secrets = {
        "keys/openrouter" = {
          owner = "sieyes";
          mode = "0400";
        };
        "keys/git/github/nrs-status" = {
          owner = "sieyes";
          mode = "0400";
        };
      };

    };

  }
]
