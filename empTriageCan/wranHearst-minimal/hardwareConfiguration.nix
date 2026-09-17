{ pkgs, ... }: {
  hardware = {
    graphics = {
      enable = true; # this is opengl; needed for sway
    };
    cpu.intel.updateMicrocode = pkgs.lib.mkDefault true;
    enableRedistributableFirmware = true; # journalctl -b will report firmware failures otherwise; sway will fail to run; the wireless interface will not be recognized
  };
}
