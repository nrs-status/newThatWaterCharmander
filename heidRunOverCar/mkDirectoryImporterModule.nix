{ pkgsLib, ... }:
dirPath: {
  imports = pkgsLib.pipe (builtins.readDir dirPath) [
    (pkgsLib.filterAttrs (
      name: type: type == "regular" && pkgsLib.hasSuffix ".nix" name && name != "default.nix"
    ))
    (pkgsLib.mapAttrsToList (name: _: dirPath + "/${name}"))
  ];
}
