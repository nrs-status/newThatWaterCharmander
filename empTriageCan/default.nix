{ baseLib }:
baseLib.importPairsOfDirPath {
  dirPath = ./.;
  pred = x:
    (dirOf x == ./.) && baseNameOf x != "default.nix"
    && !(builtins.elem (baseNameOf x) [ "louSelfHit-sofa" "heg-twPlant" ]);
  excludeDirectories = false;
}
