{ pkgsLib, ... }:
{
  virtualisation.vmVariant = {
    services = {
      qemuGuest.enable = true; #allows host to query the vm
      spice-vdagentd.enable = true; #clipboard sync agent
    };
    users.users.root.initialPassword = "rootpwd";
    virtualisation = {
      diskSize = 30000;
      memorySize = 4096;
      cores = 4;
      graphics = true; #keeps console=tty0 console=ttyS0 available
      qemu.options = [
        "-display none" #no local window, graphical access goes through SPICE
        "-serial mon:stdio" #connects VM's emulated serial port to host user's terminal. This is what allows to get a login shell

        #spice display + vdagent channel for clipboard sharing
        "-vga qxl" 
        "-spice port=5901,addr=127.0.0.1,disable-ticketing=on"
        "-device virtio-serial-pci"
        "-chardev spicevmc,id=vdagent0,name=vdagent"
        "-device virtserialport,chardev=vdagent0,name=com.redhat.spice.0"

      ];
    };
  };
}
