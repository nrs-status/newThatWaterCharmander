{ diskoFlake, ... }:
{
  imports = [ diskoFlake.nixosModules.disko ];

  disko.devices.disk.main = {
    # stable path, NOT /dev/sda: when installing from a live USB the USB stick
    # can be enumerated as sda, in which case running disko against /dev/sda
    # wipes the installer medium (or worse). by-id never changes across boots.
    # (HGST HTS541075A9E680 698G internal drive)
    device = "/dev/disk/by-id/ata-HGST_HTS541075A9E680_JD1A001918018M";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "btrfs";
            extraArgs = [ "-f" ]; # override existing partitions
            subvolumes = {
              "@" = {
                mountpoint = "/";
                mountOptions = [
                  "compress=zstd" # files on volume are always compressed
                  "noatime" # display recording file access time
                ];
              };
              "@nix" = {
                mountpoint = "/nix";
                mountOptions = [
                  "compress=zstd" # files on volume are always compressed
                  "noatime" # display recording file access time
                ];
              };
              "@persist" = {
                mountpoint = "/persist";
                mountOptions = [
                  "compress=zstd"
                  "noatime"
                ];
              };
            };
          };
        };
      };
    };
  };
}
