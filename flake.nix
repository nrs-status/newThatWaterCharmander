{
  inputs = {
    hmFlake.url = "github:nix-community/home-manager"; # the main branch is at version 26.11 at the time of creation of this flake. needs to be the same as nixpkgs, do not unpin without handling a possible change of versions or mismatch with nixpkgs because mocking home-manager to create the sway and waybar configs requires home-manager to work properly
    sopsFlake.url = "github:Mic92/sops-nix";
    diskoFlake.url = "github:nix-community/disko";
    impermanenceFlake.url = "github:nix-community/impermanence";
    mcEatBurg.url = "github:nrs-status/mcEatBurg";
    peachRampSkateboard.url = "github:nrs-status/newPeachRampSkateboard";
    frontArmToPlane.url = "github:nrs-status/newFrontArmToPlane";
    nasExitGiScorp.url = "github:nrs-status/nasExitGiScorp";
    colmenaFlake.url = "github:zhaofengli/colmena";
    direnv-instant.url = "github:Mic92/direnv-instant";
    bidGestMirror.url = "github:nrs-status/bidGestMirror";
  };

  outputs =
    inputs:
    let
      nixpkgs = inputs.mcEatBurg.nixpkgs;
      pkgsLib = inputs.peachRampSkateboard.pkgsLib; # pkgsLib is only for functionality; individual profiles specify which nixpkgs they use for non-functionality-related calls
      baseLib = inputs.peachRampSkateboard.baseLib;
      localLib = import ./heidRunOverCar {
        inherit baseLib pkgsLib;
        hmFlake = inputs.hmFlake;
        hmMockVersion = "26.11"; # used to mock hm in order to construct the waybar and sway configs
        nixosSystemFn = nixpkgs.lib.nixosSystem;
      };
      newPkgs = inputs.nasExitGiScorp.packages.x86_64-linux;
      wrappedPkgs = inputs.frontArmToPlane.packages.x86_64-linux;
      swayPkgs = inputs.bidGestMirror.packages.x86_64-linux;
      specialArgs = {
        inherit
          pkgsLib
          baseLib
          localLib
          newPkgs
          wrappedPkgs
          swayPkgs
          ;
        frontArmToPlane = inputs.frontArmToPlane; # for adding to the registry and specifying the default shell in sway
        peachRampSkateboard = inputs.peachRampSkateboard; # for adding to the registry
        sopsFlake = inputs.sopsFlake;
        diskoFlake = inputs.diskoFlake;
        impermanenceFlake = inputs.impermanenceFlake;
        localModules = import ./zeusOlympia { inherit baseLib; };
        direnv-instantFlake = inputs.direnv-instant;
      };
      hostModules = import ./empTriageCan { inherit baseLib; };
      vmModules = import ./freezCrawlTaco { inherit baseLib; };

    in
    {
      nixosConfigurations = localLib.mkNixosSystems { inherit hostModules vmModules specialArgs; };
      # VM tests (see kaounSlidesTotem/*-test); e.g. run the media-stack test with
      #   nix build .#checks.x86_64-linux.media-vm-test
      checks.x86_64-linux =
        let
          testArgs = {
            inherit pkgsLib;
            nixpkgsFlake = nixpkgs;
            sopsFlake = inputs.sopsFlake;
            impermanenceFlake = inputs.impermanenceFlake;
          };
        in
        {
          garage-vm-test = import ./kaounSlidesTotem/garage-test testArgs;
          headscale-vm-test = import ./kaounSlidesTotem/headscale-test testArgs;
          vaultwarden-vm-test = import ./kaounSlidesTotem/vaultwarden-test testArgs;
          forgejo-vm-test = import ./kaounSlidesTotem/forgejo-test (
            builtins.removeAttrs testArgs [ "sopsFlake" ]
          );
          xandikos-vm-test = import ./kaounSlidesTotem/xandikos-test (
            builtins.removeAttrs testArgs [ "sopsFlake" ]
          );
          media-vm-test = import ./kaounSlidesTotem/media-test (
            builtins.removeAttrs testArgs [ "sopsFlake" ]
          );
          console-glyphs-vm-test = import ./kaounSlidesTotem/console-glyphs-test (
            builtins.removeAttrs testArgs [ "sopsFlake" "impermanenceFlake" ]
          );
        };

      colmenaHive = inputs.colmenaFlake.lib.makeHive (
        {
          meta = {
            nixpkgs = import nixpkgs { system = "x86_64-linux"; };
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
              system.nixos.revision = lib.mkDefault nixpkgs.rev;
              system.nixos.versionSuffix = lib.mkDefault ".${
                lib.substring 0 8 nixpkgs.lastModifiedDate
              }.${nixpkgs.shortRev}";
              # same as the nixpkgs flake's nixosSystem: pins nixpkgs in the system registry/NIX_PATH to the flake's sources
              nixpkgs.flake.source = lib.mkDefault nixpkgs.outPath;
            };
        }
        // builtins.mapAttrs (_: hostModule: { imports = [ hostModule ]; }) (
          builtins.removeAttrs hostModules [
            "wranHearst"
            "wranHearst-minimal"
            "wranHearst-gui"
          ]
        )
      );
    };
}
