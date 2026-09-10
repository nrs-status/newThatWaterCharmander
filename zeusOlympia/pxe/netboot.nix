# Builds the NixOS netboot installer image that is served over TFTP.
#
# The image is built from the same nixpkgs as the host system, using the
# stock `nixos/modules/installer/netboot/netboot-minimal.nix` module, whose
# initrd embeds the whole Nix store as a squashfs. This means the client
# needs nothing but TFTP/DHCP to reach a full NixOS installer (with
# `nixos-install` and a bundled nixpkgs channel included by the
# installation-device profile).
{ config, lib, pkgs, ... }:
let
  cfg = config.services.pxeServer;

  netbootSystem = import (pkgs.path + "/nixos/lib/eval-config.nix") {
    system = "x86_64-linux";
    modules =
      [
        (pkgs.path + "/nixos/modules/installer/netboot/netboot-minimal.nix")
      ]
      ++ cfg.netbootModules;
  };
  nb = netbootSystem.config;

  # kernelFile is "bzImage" on x86_64-linux; the ipxe script produced by
  # nixos' netboot module references the same file names.
  tftpRoot = pkgs.linkFarm "pxe-tftp-root" [
    {
      name = nb.system.boot.loader.kernelFile;
      path = "${nb.system.build.kernel}/${nb.system.boot.loader.kernelFile}";
    }
    {
      name = "initrd";
      path = "${nb.system.build.netbootRamdisk}/initrd";
    }
    {
      name = "netboot.ipxe";
      path = "${nb.system.build.netbootIpxeScript}/netboot.ipxe";
    }
    {
      name = "ipxe.efi";
      path = "${pkgs.ipxe}/ipxe.efi";
    }
    {
      name = "undionly.kpxe";
      path = "${pkgs.ipxe}/undionly.kpxe";
    }
  ];
in
{
  services.pxeServer.tftpRoot = lib.mkIf cfg.enable (lib.mkDefault tftpRoot);
}