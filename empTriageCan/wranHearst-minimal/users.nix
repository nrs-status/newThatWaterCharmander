{ frontArmToPlane, localModules, ... }:
{

  imports = with localModules; [ shellCacher ];



  shellCacher.shell = frontArmToPlane.devShells.x86_64-linux.sieyes;
  # last-resort fallback for the shellCacher launcher (see zeusOlympia/shellCacher.nix)
  shellCacher.flakeRef = "frontArmToPlane#sieyes";

  users.users = {
    root.hashedPassword = "$y$j9T$m4Vx2ODhybLUlsKC9NyB30$L01GM5ntWJafyLQ3O9hyktv7vKgqMGE93RmwT8kbs96";
    sieyes = {
      isNormalUser = true;
      extraGroups = [
        "wheel"
        "docker"
        "networkmanager"
        "audio"
        "video"
        "keyd"
      ];
      hashedPassword = "$y$j9T$m4Vx2ODhybLUlsKC9NyB30$L01GM5ntWJafyLQ3O9hyktv7vKgqMGE93RmwT8kbs96"; };
  };
}
