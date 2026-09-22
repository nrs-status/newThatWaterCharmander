{ pkgs, localLib, newPkgs, wrappedPkgs, pkgsLib, config, ... }: {
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
        waybarStyle = import ./waybarStyle.nix;
        waybarConfigDeriv = localLib.mkWaybarConfig {
          inherit pkgs waybarStyle;
          waybarNixConfig = import ./waybarDecl.nix { inherit pkgs pkgsLib; };
        };
        # `waybarCommand` is run by sway's `exec` startup below. It must point at
        # the `waybar` *executable* (`pkgs.waybar` alone expands to the package
        # directory, which is not executable) and carry both the generated
        # config and the generated stylesheet.
        waybarStyleDeriv = pkgs.writeText "waybar-style.css" waybarStyle;
        swayConfigDeriv = localLib.mkSwayConfig {
          inherit pkgs;
          swayNixConfig = import ./swayDecl.nix {
            inherit pkgs newPkgs wrappedPkgs pkgsLib config;
            waybarCommand = "${pkgsLib.getExe pkgs.waybar} --config ${waybarConfigDeriv} --style ${waybarStyleDeriv}";
          };
        };
      in [ "--config=${swayConfigDeriv}" ];
    };
  };
}
