{
  localModules,
  pkgs,
  pkgsLib,
  ...
}:
{
  imports = [ localModules.libvirtd ];

  config =
    let

      testUser = "sieyes";
      # throwaway credentials, only valid inside the VM (never on the host). The
      # hashed form is the sha512-crypt hash of "swaytest" (the ssh wrapper below
      # uses the plaintext). hashedPassword is used directly by the user module,
      # sidestepping the initialPassword/hashedPassword precedence ambiguity.
      testPassword = "swaytest";
      testPasswordHash = "$6$kwTI7F.iHFa07.Wj$j8NP9EvDnM2cD7rI26Nt21bsHkM52ixmLzpTgGhWvw89CI8vjXVvadiwCoZckjIFIrfGxDLr5ZmbB.ZHMu8Yp/";
      # host port the guest's sshd is reachable on
      sshHostPort = 2222;

      # a viewer window for the VM's compositor, usable from the host at any time.
      # `remote-viewer` (not `virt-viewer`) is the client that takes a display URI.
      wranHearstVmView = pkgs.writeShellScriptBin "wranHearst-vm-view" ''
        exec ${pkgsLib.getExe' pkgs.virt-viewer "remote-viewer"} \
          "spice://127.0.0.1:5901" "$@"
      '';

      # run one command (or open a shell) inside the running test VM
      # requires `sshpass`
      wranHearstVmSsh = pkgs.writeShellScriptBin "wranHearst-vm-ssh" ''
        exec ${pkgsLib.getExe pkgs.sshpass} -p ${pkgsLib.escapeShellArg testPassword} \
          ${pkgsLib.getExe pkgs.openssh} -p ${toString sshHostPort} \
          -o StrictHostKeyChecking=no \
          -o UserKnownHostsFile=/dev/null \
          -o LogLevel=ERROR \
          ${testUser}@127.0.0.1 "$@"
      '';
    in

    {
      virtualisation.vmVariant = {

        boot = {
          # the VM runner boots the kernel directly, no boot loader (and the
          # systemd-boot/EFI setup from ./boot.nix makes no sense in a guest)
          loader.systemd-boot.enable = pkgsLib.mkForce false;
          loader.efi.canTouchEfiVariables = pkgsLib.mkForce false;

          # ./boot.nix loads the Intel iGPU driver and the host's KVM module. The
          # guest has neither device; keep the input drivers a virtual machine
          # actually needs (virtio keyboard + usb-tablet) and drop the rest.
          initrd.kernelModules = pkgsLib.mkForce [
            "usbhid"
            "joydev"
          ];
          kernelModules = pkgsLib.mkForce [
            "atkbd"
            "ctr"
            "loop"
            "tun"
            "uinput"
          ];
        };

        hardware.cpu.intel.updateMicrocode = pkgsLib.mkForce false;

        services = {
          qemuGuest.enable = true; # allows host to query the vm
          spice-vdagentd.enable = true; # clipboard sync agent

          # start the compositor automatically on tty1. `agetty --autologin` runs
          # the user's login shell; the snippet below (from programs.bash, see
          # 3.) detects tty1 and execs sway. This mirrors the pattern used by
          # nixpkgs' own nixos/tests/sway.nix.
          getty.autologinUser = testUser;

          openssh = {
            # ./openssh.nix disables password auth on the host; inside the VM the
            # throwaway password above is the simplest way for an agent to get a
            # session without provisioning a key pair.
            settings.PasswordAuthentication = pkgsLib.mkForce true;
            settings.PermitRootLogin = pkgsLib.mkForce "yes";
          };
        };

        # force the throwaway credentials (the host's hashedPassword is unknown and
        # deliberately not reused).
        users.users.${testUser}.hashedPassword = pkgsLib.mkForce testPasswordHash;
        users.users.root.hashedPassword = pkgsLib.mkForce testPasswordHash;

        # an account for serial-console poking around
        users.users.vm-user = {
          isNormalUser = true;
          extraGroups = [ "wheel" ];
          initialPassword = "userpwd";
        };

        virtualisation = {
          forwardPorts = [
            {
              from = "host";
              host.port = sshHostPort;
              guest.port = 22;
            }
          ];

          qemu.options = [
          "-display none" # no local window, graphical access goes through SPICE/VNC
          "-serial mon:stdio" # connects VM's emulated serial port to host user's terminal. This is what allows to get a login shell

          #spice display + vdagent channel for clipboard sharing
          "-vga qxl"
          "-spice port=5901,addr=127.0.0.1,disable-ticketing=on" # with this, you can run `wranHearst-vm-view` (or `remote-viewer "spice://127.0.0.1:5901"`) to get a graphical interface
          "-device virtio-serial-pci"
          "-chardev spicevmc,id=vdagent0,name=vdagent"
          "-device virtserialport,chardev=vdagent0,name=com.redhat.spice.0"

          ];
        };
      };

      environment.systemPackages = [
        pkgs.virt-viewer # provides `remote-viewer`, used by wranHearst-vm-view
        pkgs.sshpass # used by wranHearst-vm-ssh
        wranHearstVmView
        wranHearstVmSsh
      ];
    };
}
