{
  frontArmToPlane,
  waybarCommand,
  pkgs,
  pkgsLib,
config,
  ...
}:
let
  gruvbox = import ./gruvboxColors.nix;
in
{
  enable = true;
  config = rec {
    bars = [ { command = waybarCommand; } ];

    colors = {
      background = gruvbox.dark.bg;
      focused = {
        background = gruvbox.dark.bg;
        border = gruvbox.dark.bg;
        childBorder = gruvbox.dark.bg2;
        indicator = gruvbox.dark.bg4;
        text = gruvbox.dark.fg;
      };
      focusedInactive = {
        background = gruvbox.dark.bg;
        border = gruvbox.dark.bg;
        childBorder = gruvbox.dark.bg0_h;
        indicator = gruvbox.dark.bg0_h;
        text = gruvbox.dark.gray;
      };
      "placeholder" = {
        background = gruvbox.dark.bg0_s;
        border = gruvbox.dark.bg0_s;
        childBorder = gruvbox.dark.bg0_s;
        indicator = gruvbox.dark.bg0_s;
        text = gruvbox.dark.fg;
      };
      unfocused = {
        background = gruvbox.dark.bg2;
        border = gruvbox.dark.bg;
        childBorder = gruvbox.dark.bg0_h;
        indicator = gruvbox.dark.bg0_h;
        text = gruvbox.dark.gray;
      };
      urgent = {
        background = gruvbox.light.red.normal;
        border = gruvbox.light.red.normal;
        childBorder = gruvbox.light.red.normal;
        indicator = gruvbox.light.red.normal;
        text = gruvbox.dark.fg;
      };
    };
    floating = {
      border = 4;
      titlebar = true;
    };
    fonts = {
      names = [ "Iosevka Proportional" ];
      size = 11.0;
    };

    input = {
      "*" = {
        xkb_numlock = "disabled";
        xkb_layout = "us,ca(fr),es";
        xkb_options = "grp:alt_space_toggle";
      };
    };

    keybindings =
      let

        printDir = "~/daguerre_brick/rockwelllcdcalc1972";
      in
      (pkgsLib.mkOptionDefault {
        "${modifier}+Return" = "exec ${pkgsLib.getExe pkgs.kitty} nix develop ${frontArmToPlane}#sieyes";
        "${modifier}+Shift+backslash" = "splith";
        "${modifier}+minus" = "splitv";
        "${modifier}+z" = "exec killall -SIGUSR1 .waybar-wrapped";

        "${modifier}+p" = "exec --no-startup-id ${pkgs.grim}/bin/grim ${printDir}/$(date +%F-%T).png";
        "Print" =
          "exec --no-startup-id ${pkgs.grim}/bin/grim ${printDir}/$(date +%F-%T).png && wl-copy < ${printDir}/$(date +%F-%T).png";
        "${modifier}+Print" =
          ''exec --no-startup-id ${pkgs.grim}/bin/grim -g "$(slurp)" ${printDir}/snippet_$(date +%F-%T).png && wl-copy < ${printDir}/snippet_$(date +%F-%T).png'';
        "XF86AudioRaiseVolume" = "exec --no-startup-id ${pkgs.pulseaudio}/bin/pactl set-sink-volume 0 +5%";
        "XF86AudioLowerVolume" = "exec --no-startup-id ${pkgs.pulseaudio}/bin/pactl set-sink-volume 0 -5%";
        "XF86AudioMute" = "exec --no-startup-id ${pkgs.pulseaudio}/bin/pactl set-sink-mute 0 toggle";
        "${modifier}+plus" = "scratchpad show";
        "${modifier}+Shift+a" = "focus child";

        #hex color getter/picker; grab color; pipette
        "${modifier}+r" =
          ''exec grim -g "$(slurp -p)" -t ppm - | convert - -format '%[pixel:p{0,0}]' txt:- | tail -n 1 | cut -d ' ' -f 4 | wl-copy'';

          "${modifier}+l" = "exec sh -c 'pkill -x wlsunset || { ${pkgsLib.getExe pkgs.wlsunset} -T 1 -t 0 & }'";
      });

    startup = [
      { command = "mako"; }
      { command = "exec swaymsg 'workspace 1; exec ${pkgsLib.getExe pkgs.firefox}' "; }
      {
        command = "exec swaymsg 'workspace 2; exec ${pkgsLib.getExe pkgs.kitty} nix develop ${frontArmToPlane}#sieyes' ";
      }
      {
        command = ''exec ${pkgsLib.getExe pkgs.kitty} --title Scratchpad nix develop ${frontArmToPlane}#sieyes; for_window [title="Scratchpad"] move scratchpad; for_window [title="Scratchpad"] resize set width 1366 height 675'';
      }
      { command = "exec swaymsg 'exec ${pkgsLib.getExe config.programs.waybar.package}'"; }
    ];

    menu = "${pkgs.wofi}/bin/wofi --show drun";

    focus.followMouse = false;
    modifier = "Mod4";
    terminal = "${pkgs.kitty}/bin/kitty";
    gaps.smartBorders = "no_gaps";
    window = {
      border = 1;
      titlebar = false;
      commands = [
        {
          criteria = {
            app_id = "kitty";
          };
          command = "opacity 0.90";
        }
        {
          command = "opacity 0.90";
        }
      ];
    };
  };
}
