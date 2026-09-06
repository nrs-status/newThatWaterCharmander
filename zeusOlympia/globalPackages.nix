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
    git
    curl
    keyd # for monitoring keypress events
    brightnessctl # for controlling system light
    pciutils # for debugging drivers and hardware
    age #encryption
    sops #secrets manager
    ssh-to-age #for turn host ssh key into age key for allowing root to decrypt with sops
    unzip
    unrar
    fzf
    btrfs-progs # utils for btrfs
    postgresql

    #replacements for standard unix tools
    miller # replaces awk/sed/cut for structured data editing
    sd # sed replacement
    fd # `find` replacement
    trash-cli # `rm` replacement
    ripgrep # `grep` replacement
    eza # `ls` replacement
    bat # `cat` replacement
    dog # `dig` replacement
    xh # `curl` replacement
    broot # `tree` replacement
    dust # `du` replacement
    choose # `cut/awk` replacement
    duf # `df` replacement
    procs # `proc` replacement
  ];
}
