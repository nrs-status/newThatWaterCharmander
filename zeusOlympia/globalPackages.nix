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
    ssh-to-age #for turn host ssh key into age key for allowing root to decrypt with sops
  ];
}
