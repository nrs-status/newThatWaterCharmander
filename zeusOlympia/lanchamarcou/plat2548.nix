#this user is inside a host config because unlike sieyes it isn't meant to be used anywhere else than on the `lanchamarcou`
{ pkgs, ... }:
{
  users.users.plat2548 = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "docker"
      "networkmanager"
      "audio"
      "video"
    ];
    packages = with pkgs; [ zoxide btop ];
  };

}
