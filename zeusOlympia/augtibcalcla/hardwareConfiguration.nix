{ config, pkgsLib, ... }:
{
  fileSystems = {
    "/" = {
      device = "/dev/disk/by-uuid/132c0dc1-0cf2-4bc2-85dc-0d3eb4bbbb8a";
      fsType = "ext4";
    };
    "boot" = {
      device = "/dev/disk/by-uuid/CA72-5BBC";
      fsType = "vfat";
      options = [
        "fmask=0022"
        "dmask=0022"
      ];
    };
  };

  hardware = {
    cpu.amd.updateMicrocode = pkgsLib.mkDefault config.hardware.enableRedistributableFirmware;
  };
}
