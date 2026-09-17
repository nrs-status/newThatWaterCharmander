{ frontArmToPlane, localModules, pkgs, ... }:
{

  imports = [ localModules.shellCacher ];

  shellCacher.shell = frontArmToPlane.devShells.x86_64-linux.headless;


  users.users = {
    root.hashedPassword = "$y$j9T$wnwHc8mBfXipYGO2m.Ui50$YJXapso8R.AlpPbVHfYGlEH9k2kuM5vTLiZBj1rHcA/";
    plat2548 = {
      isNormalUser = true;
      extraGroups = [
        "wheel"
        "docker"
        "networkmanager"
        "audio"
        "video"
      ];
      hashedPassword = "$y$j9T$wnwHc8mBfXipYGO2m.Ui50$YJXapso8R.AlpPbVHfYGlEH9k2kuM5vTLiZBj1rHcA/";
      packages = with pkgs; [ zoxide btop ];
    };
  };
}
