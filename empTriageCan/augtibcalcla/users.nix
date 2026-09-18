{ pkgs, frontArmToPlane, localModules, ... }:
{
  imports = [ localModules.shellCacher ];

  shellCacher.shell = frontArmToPlane.devShells.x86_64-linux.headless;
  # last-resort fallback for the shellCacher launcher (see zeusOlympia/shellCacher.nix)
  shellCacher.flakeRef = "frontArmToPlane#headless";

  users.users = {
    root.hashedPassword = "$y$j9T$Oo.6EIzF0nHn5caL9b4RM0$sLXfIoJ1eXiaZoSROOqT8QkmGvNw3vNj/O8/cZ0F0C3";
    soc7099 = {
      isNormalUser = true;
      extraGroups = [
        "wheel"
        "docker"
        "networkmanager"
        "audio"
        "video"
      ];
      hashedPassword = "$y$j9T$Oo.6EIzF0nHn5caL9b4RM0$sLXfIoJ1eXiaZoSROOqT8QkmGvNw3vNj/O8/cZ0F0C3";
      packages = with pkgs; [
        zoxide
        btop
      ];
    };
  };
}
