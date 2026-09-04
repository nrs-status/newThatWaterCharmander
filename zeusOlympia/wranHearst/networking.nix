{ pkgs, ... }:
{
  networking = {
    networkmanager.enable = true;
    hostName = pkgs.lib.mkDefault "wranHearst";
    useDHCP = pkgs.lib.mkDefault true;
  };
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };
}
