# pkgsLib and pkgs are distinguished because pkgsLib is meant to provide purely adhesive code/functionality, while pkgs is meant to be used to obtain the sway packages and should be specified by a user profile
{ hmMockVersion, pkgsLib, baseLib, hmFlake, ... }:
{ swayNixConfig, pkgs }:
baseLib.withDebug rec {
  mock = (import ./mockHM.nix { inherit baseLib hmFlake hmMockVersion; } {
    inherit pkgs;
    hmMockModules = [{
      wayland.windowManager.sway = pkgsLib.mkMerge [
        {
          enable = true;
          package = null;
          systemd.enable = false;
        }
        swayNixConfig
      ];
    }];
  });
  __output = mock.config.xdg.configFile."sway/config".source;
}
