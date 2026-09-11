{ config, ... }:
{
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
    };
  };

  users.users = {
    plat2548.openssh.authorizedKeys.keys = [
      config.wranHearstPublicKey
    ];
    root.openssh.authorizedKeys.keys = [ config.wranHearstPublicKey ];
  };

  networking.firewall.allowedTCPPorts = [ 22 ];
}
