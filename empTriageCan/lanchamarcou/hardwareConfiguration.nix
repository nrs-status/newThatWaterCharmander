{ config, pkgsLib, ... }:
{
  #fileSystems are provided by the disko module from ./disko.nix; defining
  #them here as well would conflict with the disko-generated definitions

  hardware = {
    graphics.enable = true; #needed to at least get a shell
    cpu.amd.updateMicrocode = pkgsLib.mkDefault config.hardware.enableRedistributableFirmware;
    # without linux-firmware the radeon/amdgpu probe fails on the APU's GPU
    # (missing radeon/KABINI_*.bin) and the rtl8106e ethernet NIC has no
    # firmware either; the GPU failure leaves no framebuffer at all: the
    # console switches to a dummy device, so getty runs on a screen that
    # displays nothing (ssh keeps working, which makes it extra confusing)
    enableRedistributableFirmware = true;
  };

  boot.kernelParams = [
    # this APU (Kabini, CIK family) is claimed by both radeon and amdgpu;
    # amdgpu refuses CIK by default and the legacy radeon driver takes over.
    # Force amdgpu (the maintained driver) to claim it instead.
    "amdgpu.cik_support=1"
    "radeon.cik_support=0"
  ];
}
