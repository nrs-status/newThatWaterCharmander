{ diskoFlake, ... }:
{
  imports = [ diskoFlake.nixosModules.disko ];

  disko.devices.disk.main = {
    device = "/dev/disk/by-uuid/a73a03e7-3159-4656-9e1b-95f92634b4f3";
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
