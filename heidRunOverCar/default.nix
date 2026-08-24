inputs: inputs.baseLib.importPairsOfDirPath {
  pred = filePath: (builtins.elem (baseNameOf filePath) [ "default.nix" "INFO" ]) == false;
  dirPath = ./.; 
  inputsForImportPairs = inputs ;
}
