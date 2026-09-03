{ sopsFlake, ... }:
{
  imports = [ sopsFlake.nixosModules.sops ];

  security = {
    rtkit.enable = true;
    #passwordless access to rfkill so bluetooth can be toggled
    sudo.extraRules = [
      {
        groups = [ "wheel" ];
        commands = [
          {
            command = "/run/current-system/sw/bin/rfkill";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];
  };

}
