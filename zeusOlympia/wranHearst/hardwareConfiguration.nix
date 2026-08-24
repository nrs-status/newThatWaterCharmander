{ pkgs, ... }: {
  fileSystems = {
    "/" = {
      device = "/dev/disk/by-uuid/a73a03e7-3159-4656-9e1b-95f92634b4f3";
      fsType = "ext4";
    };
    "/boot" = {
      device = "/dev/disk/by-uuid/1164-B295";
      fsType = "vfat";
      options = [ "fmask=0077" "dmask=0077" ];
    };

  };
  hardware = {
    graphics = {
      enable = true; # this is opengl; needed for sway
    };
    cpu.intel.updateMicrocode = pkgs.lib.mkDefault true;
    enableRedistributableFirmware =
      true; # journalctl -b will report firmware failures otherwise; sway will fail to run; the wireless interface will not be recognized
  };
}
