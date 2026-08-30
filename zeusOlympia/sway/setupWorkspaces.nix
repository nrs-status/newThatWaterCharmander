{ pkgs, pkgsLib, frontArmToPlane }:
pkgs.writeShellApplication {
  name = "setupWorkspaces";
  text = ''
#!/usr/bin/env bash
set -euo pipefail

#setup scratchpad

WIDTH=1366
HEIGHT=765

swaymsg exec kitty
sleep 0.5 # Wait for the new window to appear and gain focus
swaymsg resize set width "$WIDTH" height "$HEIGHT"
sleep 0.2 # Small delay to let the resize apply before moving off-screen
swaymsg move scratchpad

#setup workspace 1 and 2

exec swaymsg "workspace 1; exec ${pkgsLib.getExe frontArmToPlane.packages.x86_64-linux.firefox}"
exec swaymsg "workspace 2; exec ${pkgsLib.getExe pkgs.kitty} nix develop ${frontArmToPlane}#sieyes"
'';
}

