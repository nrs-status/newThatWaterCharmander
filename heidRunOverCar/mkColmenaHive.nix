{ baseLib, pkgsLib, makeColmenaHiveFn, ... }: 
{ modulesPath, nixosSystemArgsPath, inputsForModulesExceptPkgs, colmenaArgOverrideFn }: #the 'pkgs' input is handled by nixosSystemFn so it doesn't need to be explicitly declared anywhere. pkgsLib is unrelated; it only provides functionality i.e. glue code
baseLib.withDebug rec {
  importPairs = baseLib.importPairsOfDirPath {
    pred = path: baseNameOf path != "INFO";
    dirPath = nixosSystemArgsPath;
    inputsForImportPairs = inputsForModulesExceptPkgs;
  };
  withCorrectModulesRootAux = _: nixosSystemArg: nixosSystemArg // { modules = map (modulePath: pkgsLib.path.append modulesPath modulePath) nixosSystemArg.modules; };
  withCorrectModulesRoot = builtins.mapAttrs withCorrectModulesRootAux importPairs;
  __output = makeColmenaHiveFn (colmenaArgOverrideFn withCorrectModulesRoot);
  __activateDebug = false;
}
