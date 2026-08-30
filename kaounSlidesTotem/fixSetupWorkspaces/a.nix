with builtins;
let
  total = rec {
    hmFlake = getFlake "github:nix-community/home-manager";
    nixpkgs = getFlake "github:NixOS/nixpkgs/nixos-unstable";
    baseLib = (getFlake "github:nrs-status/newPeachRampSkateboard").baseLib;
    pkgs = (import nixpkgs { system = "x86_64-linux"; });
    pkgsLib = pkgs.lib;
    frontArmToPlane = getFlake "github:nrs-status/newFrontArmToPlane";
    x = import ../../zeusOlympia/sway/setupWorkspaces.nix { inherit pkgs pkgsLib frontArmToPlane; };
  };
in total
