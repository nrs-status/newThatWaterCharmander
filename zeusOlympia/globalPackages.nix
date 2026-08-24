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
      keyd
      ripgrep
      eza
      bat
    brightnessctl
      pciutils # for debugging drivers and hardware
    ];
}
