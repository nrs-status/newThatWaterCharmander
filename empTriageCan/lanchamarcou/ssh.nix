
{ config, ... }:
{
  users.users = {
    plat2548.openssh.authorizedKeys.keys = [
      config.miscStaticVals.wranHearstPublicKey
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOeBx56er3MY5ynu0m+GyLRvov52fwIBOJJ/PzaxFxPb sieyes@wranHearst -> plat2548@lanchamarcou"
    ];
    root.openssh.authorizedKeys.keys = [ config.miscStaticVals.wranHearstPublicKey ];
  };

  networking.firewall.allowedTCPPorts = [ 22 ];
}
