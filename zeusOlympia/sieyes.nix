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


  }
]
