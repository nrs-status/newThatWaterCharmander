# pkgsLib and pkgs are distinguished because pkgsLib is meant to provide purely adhesive code/functionality, while pkgs is meant to be used to obtain the waybar packages and should be specified by a user profile
{ hmMockVersion, pkgsLib, baseLib, hmFlake, ... }:
{ pkgs, waybarStyle, waybarNixConfig }:
baseLib.withDebug rec {
  mock = (import ./mockHM.nix { inherit baseLib hmFlake hmMockVersion; } {
    inherit pkgs;
    hmMockModules = [{
      programs.waybar = pkgsLib.mkMerge [
        {
          enable = true;
          package = null;
          style = waybarStyle;
        }
        waybarNixConfig
      ];
    }];
  });
  __output = mock.config.xdg.configFile."waybar/config".source;
}
