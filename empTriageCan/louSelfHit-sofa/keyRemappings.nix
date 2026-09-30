#you can use `sudo keyd monitor` to monitor inputs
#
# Left-hand homerow toggle: `a`, `s` and `d` are remapped with `overloadt`
# (hold -> meta/alt/control, tap -> letter). Pressing the toggle key
# (`keyRemappings.lhsHomerowToggleKey`, default f21) flips a runtime
# keyd layer toggle: activating the `lhsOff` layer, whose identity bindings
# (`a = a`, `s = s`, `d = d`) occlude the main-layer overloadt remaps (layers
# are consulted in activation order, most recently activated first), so the
# keys return to their normal use; pressing it again deactivates the layer
# and restores the overloadt remaps. This is a live keyd layer operation: no
# daemon restart is involved, and it works identically in sway and on the
# console. The toggle state resets whenever keyd restarts (e.g. on reboot or
# `systemctl restart keyd`): the remaps are always active at daemon start.
#
# The current toggle state can be inspected with `sudo keyd listen`
# (prints `+lhsOff` when the keys are normal and `-lhsOff` when remapped);
# `sudo keyd monitor` shows raw device events.
{
  config,
  lib,
  ...
}:
let
  cfg = config.keyRemappings;
in
{
  options.keyRemappings = {
    # keyd key name (see `keyd list-keys`) used to toggle the a/s/d remaps.
    # f21 (evdev keycode 191) is deliberately unused elsewhere: no binding
    # below ever *emits* f21, so it cannot collide with sway's bindcode 191
    # (XF86Tools, see sway/swayDecl.nix) — that fires on keyd's emitted f13
    # (evdev 183), while this toggle consumes the physical *input* key f21.
    # Change it if your keyboard does not produce f21.
    lhsHomerowToggleKey = lib.mkOption {
      type = lib.types.str;
      default = "f21";
      description = ''
        Key that toggles the left-hand homerow a/s/d overloadt remaps at
        runtime (press once: a/s/d revert to normal letters; press again:
        remaps restored).
      '';
    };
  };

  config = {
    services.keyd = {
      enable = true;
      keyboards = {
        default = {
          ids = [ "*" ];
          settings = {
            main = {
              leftcontrol = "capslock";
              rightalt = "f13"; #keyd key names are lowercase; emitting evdev f13 (keycode 183), which sway sees as xkb keycode 191. NB: under sway's default xkb symbol set (inet(evdev)) keycode 191 yields the keysym XF86Tools, not F13, so sway binds it via `bindcode 191` (see sway/swayDecl.nix). F13 is unused otherwise; this binding is for activating voice transcription
              capslock = "layer(custom2)";
              meta = "layer(custom2)";

              # runtime a/s/d toggle (see file header): permanently toggles
              # the lhsOff layer, whose identity bindings shadow the a/s/d
              # overloadt remaps below while it is active
              "${cfg.lhsHomerowToggleKey}" = "toggle(lhsOff)";

              "a" = "overloadt(meta, a, 130)";
              "s" = "overloadt(alt, s, 130)";
              "d" = "overloadt(control, d, 130)";
              "f" = "overloadt(shift, f, 130)";

              "h" = "overloadt(shift, h, 130)";
              "j" = "overloadt(control, j, 130)";
              "k" = "overloadt(alt, k, 130)";
              "l" = "overloadt(meta, l, 130)";

              "1" = "!";
              "2" = "@";
              "3" = "#";
              "4" = "$";
              "5" = "%";
              "6" = "^";
              "7" = "&";
              "8" = "*";
              "9" = "(";
              "0" = ")";
            };
            # occluding layer for the a/s/d toggle: identity bindings that
            # make the keys emit their normal letters while the layer is
            # toggled on (see `toggle(lhsOff)` in main)
            "lhsOff" = {
              "a" = "a";
              "s" = "s";
              "d" = "d";
            };
            "custom2:211" = {
              "kp1" = "1";
              "kp2" = "2";
              "kp3" = "3";
              "kp4" = "4";
              "kp5" = "5";
              "kp6" = "6";
              "kp7" = "7";
              "kp8" = "8";
              "kp9" = "9";
              "kp0" = "0";
            };
          };
        };
      };
    };
  };
}