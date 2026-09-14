{ pkgs, localLib, frontArmToPlane, pkgsLib, config, ... }: {
  environment.systemPackages = with pkgs; [
    grim # screenshot tool
    slurp # allows selecting a piece of screen for screenshot
    wl-clipboard # wl-copy and wl-paste for copy/paste from stdin / stdout
    mako # notification system developed by swaywm maintainer
    wev # xev analogue
    remontoire # list keybindings
    killall # for toggling swaybar
    wlsunset # orange shift
    wvkbd # virtual keyboard
    libnotify #contains `notify-send`, used to send notifications via `mako`
    # Nerd Fonts: `waybarDecl.nix` uses Material Design icon codepoints
    # (U+F0001–U+F1AF0, Private Use Area) and `waybarStyle.nix`/`swayDecl.nix`
    # request the Iosevka family; without these the icons render as tofu and
    # Iosevka silently falls back to DejaVu Sans.
    nerd-fonts.iosevka # "Iosevka Nerd Font" (+Mono/Propo) variants
    nerd-fonts.symbols-only # "Symbols Nerd Font" fallback for icon codepoints in any font stack
    iosevka # plain "Iosevka" family, matching the `Iosevka Proportional` request in `swayDecl.nix`
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
          waybarNixConfig = import ./waybarDecl.nix { inherit pkgs pkgsLib; };
        };
        swayConfigDeriv = localLib.mkSwayConfig {
          inherit pkgs;
          swayNixConfig = import ./swayDecl.nix {
            inherit pkgs frontArmToPlane pkgsLib config;
            waybarCommand = "${pkgs.waybar} --config ${waybarConfigDeriv}";
          };
        };
      in [ "--config=${swayConfigDeriv}" ];
    };
  };
}
