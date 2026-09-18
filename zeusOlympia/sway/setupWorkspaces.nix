{ pkgs, pkgsLib, frontArmToPlane, devShellCommand ? "nix develop frontArmToPlane#sieyes" }:
pkgs.writeShellApplication {
  name = "setupWorkspaces";
  # `devShellCommand` is passed by swayDecl.nix: the shellCacher launcher's
  # absolute path when the shellCacher module is imported (enters the recorded
  # dev shell without evaluating the flake), or the registry flake ref
  # ("nix develop frontArmToPlane#sieyes") otherwise. In both cases it is
  # interpolated verbatim into the command sway executes, so it may contain
  # spaces (sway runs `exec` through the shell).
  meta.mainProgram = "setupWorkspaces";
  text = ''
    #!/usr/bin/env bash
    set -euo pipefail

    #setup scratchpad

    WIDTH=1366
    HEIGHT=765

    swaymsg exec ${pkgsLib.getExe pkgs.kitty} ${devShellCommand}
    sleep 0.5 # Wait for the new window to appear and gain focus
    swaymsg resize set width "$WIDTH" height "$HEIGHT"
    sleep 0.2 # Small delay to let the resize apply before moving off-screen
    swaymsg move scratchpad

    #setup workspace 1 and 2

    swaymsg "workspace 1; exec ${pkgsLib.getExe frontArmToPlane.packages.x86_64-linux.firefox}"
    swaymsg "workspace 2; exec ${pkgsLib.getExe pkgs.kitty} ${devShellCommand}"
  '';
}
