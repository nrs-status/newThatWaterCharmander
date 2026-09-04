{
  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    supportedFilesystems = [ "ntfs" ];
    initrd = {
      availableKernelModules = [
        "xhci_pci" # driver for pci-attached usb ports
        "ehci_pci" # driver for older usb 2.0
        "usbhid" # driver for usb keyboards, usb mice, etc.
        "usb_storage"
        "sd_mod" # driver for SATA/USB disks to appear as /dev/sda, /dev/sdb, etc.
        "r8169" # driver for realtek ethernet 
        "rtl8188ee" # driver for realtek wifi adapter
        "amdgpu"
        "sr_mod" # cd/dvd driver
      ];
    };
    kernelModules = [ "kvm-amd" ];
  };
}
