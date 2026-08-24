with builtins;
let
  total = rec {
    hmFlake = getFlake "github:nix-community/home-manager";
    nixpkgs = getFlake "github:NixOS/nixpkgs/nixos-unstable";
    baseLib = (getFlake "github:nrs-status/newPeachRampSkateboard").baseLib;
    pkgsLib = (import nixpkgs { system = "x86_64-linux"; }).lib;
    localLib = import ../../heidRunOverCar {
      inherit baseLib pkgsLib;
      hmFlake = inputs.hmFlake;
      hmMockVersion =
        "26.11"; # used to mock hm in order to construct the waybar and sway configs
      nixosSystemFn = nixpkgs.lib.nixosSystem;
    };
    x = localLib.mkNixOS {
      modulesPath = ../../zeusOlympia;
      nixosSystemArgsPath = ../../empTriageCan;
      inputsForModulesExceptPkgs = { inherit pkgsLib baseLib localLib; };
    };
  };
in total
