#this user is inside a host config because unlike sieyes it isn't meant to be used anywhere else than on the `lanchamarcou`
{ pkgs, pkgsLib, localLib, frontArmToPlane, ... }:
pkgsLib.mkMerge [
  #pre-warm the host's shell (`headless`) so terminals open instantly after a rebuild
  (localLib.mkShellCachingModule { inherit pkgs; shell = frontArmToPlane.devShells.x86_64-linux.headless; })

  {
    users.users.plat2548 = {
      isNormalUser = true;
      extraGroups = [
        "wheel"
        "docker"
        "networkmanager"
        "audio"
        "video"
      ];
      packages = with pkgs; [ zoxide btop ];
    };
  }
]
