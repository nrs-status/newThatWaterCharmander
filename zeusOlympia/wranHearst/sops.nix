{ pkgsLib, sopsFlake, ...}:
pkgsLib.mkMerge [
  sopsFlake.nixosModules.sops
]

