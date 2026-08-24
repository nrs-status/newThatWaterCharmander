rec {
  dark = rec {
    black = rec {
      normal = "#282828";
      bright = "#928374";
    };
    red = {
      normal = "#cc241d";
      bright = "#fb4934";
    };
    green = {
      normal = "#98971a";
      bright = "#b8bb26";
    };
    yellow = {
      normal = "#d79921";
      bright = "#fabd2f";
    };
    blue = {
      normal = "#458588";
      bright = "#83a598";
    };
    purple = {
      normal = "#b16286";
      bright = "#d3869b";
    };
    cyan = {
      normal = "#689D6a";
      bright = "#8ec07c";
    };
    white = {
      normal = "#a89984";
      bright = "#ebdbb2";
    };
    orange = {
      normal = "#d65d0e";
      bright = "#fe8019";
    };
    bg = black.normal;
    bg0_h = "#1d2021"; # high contrast background
    bg0_s = "#32302f"; # low contrast background
    bg0 = bg;
    bg1 = "#3c3836";
    bg2 = "#504945";
    bg3 = "#665c54";
    bg4 = "#7c6f64";
    fg = white.bright;
    fg0 = "#fbf1c7";
    fg1 = fg;
    fg2 = "#d5c4a1";
    fg3 = "#BDAE93";
    fg4 = "#a89984";
    gray = "#928374";
  };
  light = rec {
    black = {
      normal = dark.fg0;
      inherit (dark.black) bright;
    };
    red = {
      inherit (dark.red) normal;
      bright = "#9d0006";
    };
    green = {
      inherit (dark.green) normal;
      bright = "#79740e";
    };
    yellow = {
      inherit (dark.yellow) normal;
      bright = "#B57614";
    };
    blue = {
      inherit (dark.blue) normal;
      bright = "#076678";
    };
    purple = {
      inherit (dark.purple) normal;
      bright = "#8f3f71";
    };
    cyan = {
      inherit (dark.cyan) normal;
      bright = "#427b58";
    };
    white = {
      normal = dark.bg4;
      bright = dark.bg1;
    };
    orange = {
      inherit (dark.orange) normal;
      bright = "#af3a03";
    };
    bg = light.black.normal;
    bg0_h = "#f9f5d7"; # high contrast background
    bg0_s = "#f2e5bc"; # low contrast background
    bg0 = bg;
    bg1 = dark.fg1;
    bg2 = dark.fg2;
    bg3 = dark.fg3;
    bg4 = dark.fg4;
    fg = dark.bg1;
    fg0 = dark.bg0;
    fg1 = fg;
    fg2 = dark.bg2;
    fg3 = dark.bg3;
    fg4 = dark.bg4;
    gray = dark.fray;
  };
}
