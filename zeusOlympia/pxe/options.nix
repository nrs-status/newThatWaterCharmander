{ lib, ... }:
let
  inherit (lib)
    mkOption
    types
    ;
in
{
  options.services.pxeServer = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to run the PXE server: DHCP + TFTP (via dnsmasq) serving a
        NixOS netboot installer over a directly cabled ethernet interface.
      '';
    };

    interface = mkOption {
      type = types.str;
      example = "enp3s0";
      description = ''
        The ethernet interface cabled to the client machine. DHCP, TFTP and
        (if `externalInterface` is set) NAT are bound to this interface, and
        the server address (`serverIp`) is assigned to it.
      '';
    };

    serverIp = mkOption {
      type = types.str;
      default = "10.0.0.1";
      description = ''
        Static IPv4 address assigned to `interface`; it doubles as the DHCP
        gateway, DNS server and TFTP server for the client.
      '';
    };

    prefixLength = mkOption {
      type = types.ints.between 8 30;
      default = 24;
      description = ''
        Prefix length of the server/client subnet.
      '';
    };

    dhcpStart = mkOption {
      type = types.str;
      default = "10.0.0.100";
      description = ''
        First IPv4 address of the DHCP pool handed out to clients.
      '';
    };

    dhcpEnd = mkOption {
      type = types.str;
      default = "10.0.0.200";
      description = ''
        Last IPv4 address of the DHCP pool handed out to clients.
      '';
    };

    leaseTime = mkOption {
      type = types.str;
      default = "12h";
      description = ''
        DHCP lease duration.
      '';
    };

    externalInterface = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "enp2s0";
      description = ''
        Internet-facing interface to NAT the client traffic through, so the
        installed/netbooted machine can reach the network. `null` disables
        NAT entirely.
      '';
    };

    netbootModules = mkOption {
      type = types.listOf types.raw;
      default = [ ];
      example = lib.literalExpression "[ { services.openssh.enable = true; } ]";
      description = ''
        Extra NixOS modules applied to the netboot installer image that is
        served to clients (on top of `netboot-minimal.nix` from nixpkgs).
      '';
    };

    tftpRoot = mkOption {
      type = types.package;
      readOnly = true;
      description = ''
        Directory (store path) served over TFTP; contains the kernel
        (`bzImage`), the initrd with the embedded Nix store squashfs
        (`initrd`), the `netboot.ipxe` script and the iPXE bootloaders
        (`ipxe.efi` for UEFI, `undionly.kpxe` for BIOS).
      '';
    };
  };
}