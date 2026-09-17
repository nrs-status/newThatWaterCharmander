{
  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    supportedFilesystems = [ "ntfs" ];
    initrd = {
      kernelModules = [
        "nvme" # ssd driver
        "xhci_pci" # driver for pci-attached usb ports
        "usbhid" # driver for usb keyboards, usb mice, etc.
        "usb_storage"
        "sd_mod" # driver for SATA/USB disks to appear as /dev/sda, /dev/sdb, etc.
        "rtsx_pci_sdmmc" # driver for sd card slot
      ];
    };
    kernelModules = [ "kvm-amd" ];
  };
}
