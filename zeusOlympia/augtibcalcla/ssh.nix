{ config, ... }:
{

  users.users = {
    soc7099.openssh.authorizedKeys.keys = [
      config.wranHearstPublicKey
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILaLusJFoBqVL62rtO0KcpLxD6qjLg+5gmfMUitIKWrW sieyes@wranHearst -> soc7099@augtibcalcla"
    ];
    root.openssh.authorizedKeys.keys = [ config.wranHearstPublicKey ];
  };
  networking.firewall.allowedTCPPorts = [ 22 ];
}
