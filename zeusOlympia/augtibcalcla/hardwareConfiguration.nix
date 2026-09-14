{ config, pkgsLib, ... }:
{
  hardware = {
    graphics.enable = true; #needed to at least get a shell
    cpu.amd.updateMicrocode = pkgsLib.mkDefault config.hardware.enableRedistributableFirmware;

    enableRedistributableFirmware = true;
  };
}
