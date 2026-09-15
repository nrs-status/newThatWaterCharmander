{ config, ... }:
{
  users.users = {
    plat2548.openssh.authorizedKeys.keys = [
      config.wranHearstPublicKey
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFOCCo4KBdMBBBZYeKWItL1y1hEhRPDm2HIKfWGHUxkN sieyes@wranHearst -> plat2548@lanchamarcou"
    ];
    root.openssh.authorizedKeys.keys = [ config.wranHearstPublicKey ];
  };

  networking.firewall.allowedTCPPorts = [ 22 ];
}
