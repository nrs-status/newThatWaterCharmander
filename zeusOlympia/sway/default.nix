{ pkgs, localLib, frontArmToPlane, ... }: {
  environment.systemPackages = with pkgs; [
    grim # screenshot tool
    slurp # allows selecting a piece of screen for screenshot
    wl-clipboard # wl-copy and wl-paste for copy/paste from stdin / stdout
    mako # notification system developed by swaywm maintainer
    wev # xev analogue
    remontoire # list keybindings
    killall # for toggling swaybar
  ];

  programs = {
    waybar = {
      enable = true;
      package = pkgs.waybar;
    };
    sway = {
      enable = true;
      package = pkgs.sway;
      extraOptions = let
        waybarConfigDeriv = localLib.mkWaybarConfig {
          inherit pkgs;
          waybarStyle = import ./waybarStyle.nix;
          waybarNixConfig = import ./waybarDecl.nix { inherit pkgs; };
        };
        swayConfigDeriv = localLib.mkSwayConfig {
          inherit pkgs;
          swayNixConfig = import ./swayDecl.nix {
            inherit pkgs frontArmToPlane;
            waybarCommand = "${pkgs.waybar} --config ${waybarConfigDeriv}";
          };
        };
      in [ "--config=${swayConfigDeriv}" ];
    };
  };
}
