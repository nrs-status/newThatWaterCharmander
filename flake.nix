{
  inputs = {
    hmFlake.url = "github:nix-community/home-manager"; # the main branch is at version 26.11 at the time of creation of this flake. needs to be the same as nixpkgs, do not unpin without handling a possible change of versions or mismatch with nixpkgs because mocking home-manager to create the sway and waybar configs requires home-manager to work properly
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    sopsFlake.url = "github:Mic92/sops-nix";
    diskoFlake.url = "github:nix-community/disko";
    impermanenceFlake.url = "github:nix-community/impermanence";
    peachRampSkateboard.url = "github:nrs-status/newPeachRampSkateboard";
    frontArmToPlane.url = "github:nrs-status/newFrontArmToPlane";
    colmenaFlake.url = "github:zhaofengli/colmena";
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
        # nixosSystemFn = inputs.nixpkgs.lib.nixosSystem;
        # makeColmenaHiveFn = inputs.colmenaFlake.lib.makeHive;
        # nixpkgsFlake = inputs.nixpkgs;
      };
      specialArgs = {
        inherit pkgsLib baseLib localLib;
        frontArmToPlane = inputs.frontArmToPlane; # for adding to the registry and specifying the default shell in sway
        peachRampSkateboard = inputs.peachRampSkateboard; # for adding to the registry
        sopsFlake = inputs.sopsFlake;
        diskoFlake = inputs.diskoFlake;
        impermanenceFlake = inputs.impermanenceFlake;
        localModules = import ./zeusOlympia { inherit baseLib; };
      };
      hostModules = import ./empTriageCan { inherit baseLib; };
    in
    {
      nixosConfigurations = builtins.mapAttrs (
        _name: x:
        inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ x ];
          inherit specialArgs;
        }
      ) hostModules;

      colmenaHive = inputs.colmenaFlake.lib.makeHive (
        {
          meta = {
            nixpkgs = import inputs.nixpkgs { system = "x86_64-linux"; };
            inherit specialArgs;
          };
          # colmena evaluates nodes with eval-config.nix called directly from
          # the nixpkgs store path, so its lib lacks the flake-version-info
          # overlay and nodes report system.nixos.revision = null / version
          # "26.11pre-git". Restore the flake's version info so the hive's
          # toplevels match the ones built via nixosConfigurations.
          defaults =
            { lib, ... }:
            {
              system.nixos.revision = lib.mkDefault inputs.nixpkgs.rev;
              system.nixos.versionSuffix = lib.mkDefault ".${lib.substring 0 8 inputs.nixpkgs.lastModifiedDate}.${inputs.nixpkgs.shortRev}";
              # same as the nixpkgs flake's nixosSystem: pins nixpkgs in the system registry/NIX_PATH to the flake's sources
              nixpkgs.flake.source = lib.mkDefault inputs.nixpkgs.outPath;
            };
        }
        // builtins.mapAttrs (_: hostModule: { imports = [ hostModule ]; }) (
          builtins.removeAttrs hostModules [ "wranHearst" ]
        )
      );
    };
}
