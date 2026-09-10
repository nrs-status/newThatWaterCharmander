# DHCP + TFTP configuration (via dnsmasq) and the network setup needed for
# a machine cabled directly to the client.
#
# Boot file selection (see dnsmasq's find_boot: among tagged dhcp-boot
# lines, the last matching line in the file wins; untagged lines are only
# consulted when no tagged line matches):
#   - BIOS PXE ROMs (arch 0, no iPXE)  -> undionly.kpxe  (iPXE BIOS chainload)
#   - UEFI PXE (arch 7/9, no iPXE)     -> ipxe.efi       (iPXE UEFI)
#   - any iPXE client (option 175)     -> netboot.ipxe   (the NixOS netboot image)
# undionly.kpxe and ipxe.efi DHCP a second time, this time sending iPXE's
# option 175, so they get `netboot.ipxe` and boot the NixOS installer.
{ config, lib, ... }:
let
  cfg = config.services.pxeServer;

  # 24 -> "255.255.255.0", 25 -> "255.255.255.128", ...
  netmaskBytes = [
    0
    128
    192
    224
    240
    248
    252
    254
    255
  ];
  netmaskOf =
    prefixLength:
    lib.concatStringsSep "." (
      map (
        i:
        let
          bits = lib.min 8 (lib.max 0 (prefixLength - 8 * i));
        in
        toString (lib.elemAt netmaskBytes bits)
      ) [ 0 1 2 3 ]
    );
in
{
  config = lib.mkIf cfg.enable {

    networking = {
      # Static address on the interface cabled to the client; dnsmasq only
      # serves DHCP on interfaces carrying a matching subnet.
      interfaces.${cfg.interface} = {
        ipv4.addresses = [
          {
            address = cfg.serverIp;
            prefixLength = cfg.prefixLength;
          }
        ];
      };

      firewall = {
        # DHCP (67), TFTP (69); the pxe interface is trusted so client
        # traffic (including DHCP renewals) is not filtered.
        allowedUDPPorts = [
          67
          69
        ];
        trustedInterfaces = [ cfg.interface ];
      };

      # Let the client reach the internet through this server (the
      # `dhcp-option` lines below hand it this machine as gateway/DNS).
      nat = lib.mkIf (cfg.externalInterface != null) {
        enable = true;
        externalInterface = cfg.externalInterface;
        internalInterfaces = [ cfg.interface ];
      };
    };

    services.dnsmasq = {
      enable = true;
      # Don't hijack the server's own /etc/resolv.conf; dnsmasq still
      # forwards DNS for the client using the server's normal upstream
      # resolver configuration.
      resolveLocalQueries = lib.mkDefault false;

      settings = {
        # Disable nothing DNS-wise: keep DNS listening so the client can use
        # this server as its nameserver (option 6 below).
        interface = [ cfg.interface ];
        bind-interfaces = true;
        dhcp-authoritative = true;
        log-dhcp = true;

        dhcp-range = [
          "${cfg.dhcpStart},${cfg.dhcpEnd},${netmaskOf cfg.prefixLength},${cfg.leaseTime}"
        ];

        dhcp-option = [
          "3,${cfg.serverIp}" # router
          "6,${cfg.serverIp}" # DNS
        ];

        enable-tftp = true;
        tftp-root = "${cfg.tftpRoot}";

        dhcp-match = [
          "set:efi-x86_64,option:client-arch,7"
          "set:efi-x86_64,option:client-arch,9"
          "set:efi-x86_32,option:client-arch,6"
          "set:ipxe,175" # iPXE clients send option 175
        ];

        dhcp-boot = [
          "tag:efi-x86_64,ipxe.efi,${cfg.serverIp}"
          "tag:ipxe,netboot.ipxe,${cfg.serverIp}"
          "undionly.kpxe,${cfg.serverIp}" # untagged fallback: BIOS PXE ROMs
        ];
      };
    };
  };
}