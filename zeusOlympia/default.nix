inputs@{ pkgsLib, baseLib, ... }:
let
  modulePaths = baseLib.listPathsSatisfyingPred {
    pred = path: dirOf path == ./. && baseNameOf path != "default.nix";
  };
in pkgsLib.mkMerge (map (x: import x inputs) modulePaths)
