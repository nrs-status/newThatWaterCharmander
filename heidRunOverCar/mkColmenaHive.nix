{ baseLib, pkgsLib, makeColmenaHiveFn, nixpkgsFlake, ... }:
{ modulesPath, nixosSystemArgsPath, inputsForModulesExceptPkgs, colmenaArgOverrideFn }: #the 'pkgs' input is handled by nixosSystemFn so it doesn't need to be explicitly declared anywhere. pkgsLib is unrelated; it only provides functionality i.e. glue code
baseLib.withDebug rec {
  importPairs = baseLib.importPairsOfDirPath {
    pred = path: baseNameOf path != "INFO";
    dirPath = nixosSystemArgsPath;
    inputsForImportPairs = inputsForModulesExceptPkgs;
  };
  withCorrectModulesRootAux = _: nixosSystemArg: nixosSystemArg // { modules = map (modulePath: pkgsLib.path.append modulesPath modulePath) nixosSystemArg.modules; };
  withCorrectModulesRoot = builtins.mapAttrs withCorrectModulesRootAux importPairs;
  colmenaArg = colmenaArgOverrideFn withCorrectModulesRoot;
  __output = makeColmenaHiveFn ({
    meta = {
      nixpkgs = import nixpkgsFlake { system = "x86_64-linux"; };
      specialArgs = inputsForModulesExceptPkgs;
    };
  } // builtins.mapAttrs (_: nixosSystemArg: nixosSystemArg.modules) colmenaArg);
  __activateDebug = false;
}
