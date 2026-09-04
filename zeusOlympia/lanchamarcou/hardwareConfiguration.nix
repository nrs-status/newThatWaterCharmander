{ config, pkgsLib, ... }:
{
  #fileSystems are provided by the disko module from ./disko.nix; defining
  #them here as well would conflict with the disko-generated definitions

  hardware = {
    cpu.amd.updateMicrocode = pkgsLib.mkDefault config.hardware.enableRedistributableFirmware;
  };
}
