{ baseLib, pkgsLib, nixosSystemFn, ... }: 
{ modulesPath, nixosSystemArgsPath, inputsForModulesExceptPkgs }: #the 'pkgs' input is handled by nixosSystemFn so it doesn't need to be explicitly declared anywhere. pkgsLib is unrelated; it only provides functionality i.e. glue code
baseLib.withDebug rec {
  importPairs = baseLib.importPairsOfDirPath {
    pred = path: baseNameOf path != "INFO";
    dirPath = nixosSystemArgsPath;
    inputsForImportPairs = inputsForModulesExceptPkgs;
  };
  withCorrectModulesRootAux = _: nixosSystemArg: nixosSystemArg // { modules = map (modulePath: pkgsLib.path.append modulesPath modulePath) nixosSystemArg.modules; };
  withCorrectModulesRoot = builtins.mapAttrs withCorrectModulesRootAux importPairs;
  nixosEvalsAux = _: nixosSystemArg: nixosSystemFn nixosSystemArg;
  nixosEvals = builtins.mapAttrs nixosEvalsAux withCorrectModulesRoot;
  __output = nixosEvals;
  __activateDebug = false;
}
