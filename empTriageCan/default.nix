{ baseLib }:
baseLib.importPairsOfDirPath {
  dirPath = ./.;
  pred = x:
    (dirOf x == ./.) && baseNameOf x != "default.nix" && baseNameOf x != "louSelfHit-sofa" && baseNameOf != "heg-twPlant";
  excludeDirectories = false;
}
