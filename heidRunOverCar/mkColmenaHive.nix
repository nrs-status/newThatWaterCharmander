{ baseLib, pkgsLib, makeColmenaHiveFn, nixpkgsFlake, ... }:
{ modulesPath, nixosSystemArgsPath, inputsForModulesExceptPkgs, colmenaArgOverrideFn }: #the 'pkgs' input is handled by nixosSystemFn so it doesn't need to be explicitly declared anywhere. pkgsLib is unrelated; it only provides functionality i.e. glue code
baseLib.withDebug rec {
  importPairs = baseLib.importPairsOfDirPath {
    pred = path: baseNameOf path != "INFO";
    dirPath = nixosSystemArgsPath;
    inputsForImportPairs = inputsForModulesExceptPkgs;
  };
  withCorrectModulesRootAux = _: nixosSystemArg: nixosSystemArg // { modules = map (modulePath: pkgsLib.path.append modulesPath modulePath) nixosSystemArg.modules; };
  withCorrectModulesRoot = builtins.mapAttrs withCorrectModulesRootAux importPairs; #identical to mkNixos up to this point.
  colmenaArg = colmenaArgOverrideFn withCorrectModulesRoot;
  __output = makeColmenaHiveFn ({
    meta = {
      nixpkgs = import nixpkgsFlake { system = "x86_64-linux"; };
      specialArgs = inputsForModulesExceptPkgs;
    };
    # colmena evaluates nodes with eval-config.nix called directly from the nixpkgs store path, so its lib
    # lacks the flake-version-info overlay and nodes report system.nixos.revision = null / version
    # "26.11pre-git". This makes the hive's toplevels differ from the ones built via nixosConfigurations.
    # Restore the flake's version info so both outputs produce identical closures.
    defaults = { lib, ... }: {
      system.nixos.revision = lib.mkDefault nixpkgsFlake.rev;
      system.nixos.versionSuffix = lib.mkDefault ".${lib.substring 0 8 nixpkgsFlake.lastModifiedDate}.${nixpkgsFlake.shortRev}";
      # same as the nixpkgs flake's nixosSystem: pins nixpkgs in the system registry/NIX_PATH to the flake's sources
      nixpkgs.flake.source = lib.mkDefault nixpkgsFlake.outPath;
    };
  } // builtins.mapAttrs (_: nixosSystemArg: nixosSystemArg.modules) colmenaArg);
  __activateDebug = false;
}
