with builtins;
let
  total = rec {
    hmFlake = getFlake "github:nix-community/home-manager";
    nixpkgs = getFlake "github:NixOS/nixpkgs/nixos-unstable";
    baseLib = (getFlake "github:nrs-status/newPeachRampSkateboard").baseLib;
    pkgs = import nixpkgs { system = "x86_64-linux"; };
    x = import ../../heidRunOverCar/mkWaybarConfig.nix {
      inherit hmFlake pkgs baseLib;
      hmMockVersion = "26.11"; #version of home-manager used to create a mock home-manager environment
      waybarStyle = import ../../zeusOlympia/sway/waybarStyle.nix;
      waybarNixConfig = import ../../zeusOlympia/sway/waybarDecl.nix { inherit pkgs; };
    };
    y = import ../../heidRunOverCar/mkSwayConfig.nix {
      inherit hmFlake pkgs baseLib;
      hmMockVersion = "26.11";
      swayNixConfig = import ../../zeusOlympia/sway/swayDecl.nix {
        inherit pkgs;
        waybarCommand = "${pkgs.waybar} --config ${x}";
      };
    };

  };
in total
