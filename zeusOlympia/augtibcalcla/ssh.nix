{ config, ... }:
{
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
    };
  };


  users.users = {
    soc7099.openssh.authorizedKeys.keys = [
      config.wranHearstPublicKey
    ];
    root.openssh.authorizedKeys.keys = [ config.wranHearstPublicKey ];
  };
  networking.firewall.allowedTCPPorts = [ 22 ];
}
