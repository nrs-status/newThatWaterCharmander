{ pkgs, direnv-instantFlake, ... }:
{
  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    enableFishIntegration = true;
    nix-direnv.enable = true;
  };
  imports = [ direnv-instantFlake.nixosModules.direnv-instant ];
  programs.direnv-instant.enable = true;
  environment.systemPackages = with pkgs; [
    keyd # for monitoring keypress events
    brightnessctl # for controlling system light
    pciutils # for debugging drivers and hardware
    usbutils #has lsusb which was able to detect meta quest 3 on usb while lsblk did not show it
  ];
}
