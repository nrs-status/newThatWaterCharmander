{
  inputs = {
    hmFlake.url = "github:nix-community/home-manager"; # the main branch is at version 26.11 at the time of creation of this flake. needs to be the same as nixpkgs, do not unpin without handling a possible change of versions or mismatch with nixpkgs because mocking home-manager to create the sway and waybar configs requires home-manager to work properly
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    sopsFlake.url = "github:Mic92/sops-nix";
    diskoFlake.url = "github:nix-community/disko";
    impermanenceFlake.url = "github:nix-community/impermanence";
    peachRampSkateboard.url = "github:nrs-status/newPeachRampSkateboard";
    frontArmToPlane.url = "github:nrs-status/newFrontArmToPlane";
  };

  outputs =
    inputs:
    let
      pkgsLib =
        (import inputs.nixpkgs {
          system = "x86_64-linux";
        }).lib; # pkgsLib is only for functionality; individual profiles specify which nixpkgs they use for non-functionality-related calls
      baseLib = inputs.peachRampSkateboard.baseLib;
      localLib = import ./heidRunOverCar {
        inherit baseLib pkgsLib;
        hmFlake = inputs.hmFlake;
        hmMockVersion = "26.11"; # used to mock hm in order to construct the waybar and sway configs
        nixosSystemFn = inputs.nixpkgs.lib.nixosSystem;
      };
    in
    {
      nixosConfigurations = localLib.mkNixOS {
        modulesPath = ./zeusOlympia;
        nixosSystemArgsPath = ./empTriageCan;
        inputsForModulesExceptPkgs = {
          inherit pkgsLib baseLib localLib;
          frontArmToPlane = inputs.frontArmToPlane; #for adding to the registry and specifying the default shell in sway
          peachRampSkateboard = inputs.peachRampSkateboard; #for adding to the registry
          sopsFlake = inputs.sopsFlake;
          diskoFlake = inputs.diskoFlake;
          impermanenceFlake = inputs.impermanenceFlake;
        };
      };
    };
}
