{ config, pkgsLib, ... }:
{
  hardware = {
    cpu.amd.updateMicrocode = pkgsLib.mkDefault config.hardware.enableRedistributableFirmware;
  };
}
