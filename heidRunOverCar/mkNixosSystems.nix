{ nixpkgs, ... }:
{ hostModules, vmModules, specialArgs, ... }:
let
  mkNixosSystem =
    specialargs: x:
    nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ x ];
      specialArgs = specialargs;
    };
in

builtins.mapAttrs (_: mkNixosSystem specialArgs) hostModules
// builtins.mapAttrs (_: mkNixosSystem (specialArgs // { inherit hostModules; })) vmModules
