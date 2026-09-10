# NixOS module for a PXE server that installs NixOS on a machine
# connected to it by an ethernet cable.
#
# It provides:
#   - DHCP + TFTP via dnsmasq, bound to a single ethernet interface
#   - a NixOS netboot (installer) image built from the same nixpkgs as
#     the server, served over TFTP
#   - iPXE bootloader files (BIOS and UEFI) so that any x86_64 client
#     can chain into the netboot image
#   - optional NAT so the installing client can reach the internet
#     through this server
#
# Enable it with e.g.
#   services.pxeServer = {
#     enable = true;
#     interface = "enp3s0"; # the NIC cabled to the client machine
#   };
# and plug the client into that NIC with a (cross-over or auto-MDIX)
# ethernet cable; boot the client from network (BIOS/UEFI network boot).
{ lib, ... }:
let
  dirPath = ./.;
in
{
  imports = map (name: dirPath + "/${name}") (
    builtins.filter (
      name: lib.hasSuffix ".nix" name && name != "default.nix"
    ) (builtins.attrNames (builtins.readDir dirPath))
  );
}