{ frontArmToPlane, ... }:
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
  systemd.user.services.cacheSieyesShell =
    let
      derivExpr = frontArmToPlane.devShells.x86_64-linux.sieyes.inputDerivation;
    in
    {
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "nix build --expr ${derivExpr} --no-link --print-out-paths";

        #don't compete with rest of login sequence
        Nice = 19;
        IOSchedulingClass = "idle";
      };
    };

  #secrets management; requires that the host enable to sops module
  sops = {
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



}
