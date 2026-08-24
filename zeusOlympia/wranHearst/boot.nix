{
  boot = {
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
    supportedFilesystems = ["ntfs"];
    initrd = {
      availableKernelModules = [ "xhci_pci" "thunderbolt" "nvme" "usb_storage" "sd_mod" "sdhci_pci" ];
      kernelModules = [ 
        "usbhid" # for HID devices
        "joydev"  # for joystick
        "i915" # name of intel hd graphics driver
      ];
    };
    kernelModules = [ 
      "kvm-intel" 
    ];
  };
}
