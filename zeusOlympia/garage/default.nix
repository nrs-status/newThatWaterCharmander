# NixOS module for the Garage S3-compatible object store.
#
# https://garagehq.deuxfleurs.fr/
#
# The module is split in two files that are imported here:
#   - options.nix: declares the `services.garage` options
#   - server.nix:  derives the garage config file and systemd unit
#
# vm-test.nix is a standalone nixosTest (run via
# `nix build .#checks.x86_64-linux.garage-vm-test`), not a NixOS module, so
# it is excluded from the import set below.
{ lib, ... }:
let
  dirPath = ./.;
in
{
  imports = map (name: dirPath + "/${name}") (
    builtins.filter (
      name: lib.hasSuffix ".nix" name && name != "default.nix" && name != "vm-test.nix"
    ) (builtins.attrNames (builtins.readDir dirPath))
  );
}
