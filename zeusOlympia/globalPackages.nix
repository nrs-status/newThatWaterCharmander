{ pkgs, ... }:
{
  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    enableFishIntegration = true;
    nix-direnv.enable = true;
  };
  environment.systemPackages = with pkgs; [
    vim
    curl
    git
    keyd # for monitoring keypress events
    ripgrep
    eza
    bat
    brightnessctl # for controlling system light
    pciutils # for debugging drivers and hardware
    age #encryption
    sops #secrets manager
  ];
}
