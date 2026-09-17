{ pkgsLib, ... }:
dirPath: {
  imports = pkgsLib.pipe (builtins.readDir dirPath) [
    (pkgsLib.filterAttrs (
      name: type:
      let
        path = dirPath + "/${name}";
      in
      # regular modules: every .nix file except default.nix
      (type == "regular" && pkgsLib.hasSuffix ".nix" name && name != "default.nix")
      # subdirectories: imported via their default.nix (if they have one)
      || (type == "directory" && builtins.pathExists (path + "/default.nix"))
    ))
    # importing a directory path transparently resolves to its default.nix
    (pkgsLib.mapAttrsToList (name: _: dirPath + "/${name}"))
  ];
}
