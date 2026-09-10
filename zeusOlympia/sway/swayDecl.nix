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
        # use the `frontArmToPlane` flake-registry entry (see nix.nix) instead of
        # interpolating the flake input: the latter yields a /nix/store copy of
        # the flake containing a `.git` entry, which makes `nix develop` treat it
        # as a git repo owned by root and fail (libgit2 ownership check), killing
        # the terminal instantly.
        "${modifier}+Return" = "exec ${pkgsLib.getExe pkgs.kitty} nix develop frontArmToPlane#sieyes";
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

        "${modifier}+semicolon" =
          "exec sh -c 'pkill -x wlsunset || { ${pkgsLib.getExe pkgs.wlsunset} -T 1 -t 0 & }'";
      });

    startup = [
      { command = "mako"; }
      { command = "exec swaymsg 'exec ${pkgsLib.getExe config.programs.waybar.package}'"; }
      {
        command = "${pkgsLib.getExe (
          import ./setupWorkspaces.nix { inherit pkgs pkgsLib frontArmToPlane; }
        )}";
      }
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

      ];
    };

  };

  # keyd remaps rightalt to evdev F13 (keycode 183), which sway receives as xkb
  # keycode 191. `bindsym F13` cannot work here: sway's keymap (layouts
  # us,ca(fr),es under rules "evdev", which always appends the inet(evdev)
  # symbols) maps keycode 191 (<FK13>) to XF86Tools, and *no* keycode in the us
  # layout produces the F13 keysym (it is commented out in symbols/inet). Bind
  # the raw keycode instead of the keysym.
  extraConfig = ''
    bindcode 191 exec --no-startup-id ${pkgsLib.getExe frontArmToPlane.packages.x86_64-linux.voice-input} start
    bindcode --release 191 exec --no-startup-id ${pkgsLib.getExe frontArmToPlane.packages.x86_64-linux.voice-input} finish
  '';
}
