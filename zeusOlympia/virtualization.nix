{
  pkgs,
  pkgsLib,
  config,
  ...
}:
let
  # throwaway credentials. plaintext used by `vm-ssh` script in the last attribute below.
  # hashed form is the sha512-crypt hash of "swaytest". hashedPassword is used directly by the virtualisation.vmVariant.user.user attribute below
  testPassword = "swaytest";
  testPasswordHash = "$6$kwTI7F.iHFa07.Wj$j8NP9EvDnM2cD7rI26Nt21bsHkM52ixmLzpTgGhWvw89CI8vjXVvadiwCoZckjIFIrfGxDLr5ZmbB.ZHMu8Yp/";
in
{
  options.virtualisation = {
    sshUser = pkgsLib.mkOption {
      type = pkgsLib.types.str;
      description = "Name of a user in the guest that can be SSH'd into from the host";
    };
    sshHostPort = pkgsLib.mkOption {
      type = pkgsLib.types.port;
      description = "host port the guest's sshd is reachable on";
    };
  };

  config = {
    # The VM serial log lives under /var/log on the *host*. systemd-tmpfiles
    # creates the directory (world-writable so the unprivileged user running the
    # VM can write into it).
    systemd.tmpfiles.rules = [
      "d /var/log/vm-serial 1777 root root -"
    ];

    virtualisation = {
      libvirtd = {
        enable = true;
        qemu = {
          package = pkgs.qemu_kvm;
          runAsRoot = true;
          swtpm.enable = true;
        };
      };

      vmVariant = {
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
          getty.autologinUser = config.virtualisation.sshUser;

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
        users.users.${config.virtualisation.sshUser}.hashedPassword = pkgsLib.mkForce testPasswordHash;
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
              host.port = config.virtualisation.sshHostPort;
              guest.port = 22;
            }
          ];

          qemu.options = [
            "-display none" # no local window, graphical access goes through SPICE/VNC

            # Connect the VM's emulated serial port (ttyS0, the guest console)
            # to the host user's terminal *and* tee everything the guest writes
            # to it (kernel log + serial getty) into a per-host log file.
            # `mux=on` keeps the QEMU HMP monitor on the same stdio chardev,
            # exactly like the old `-serial mon:stdio`; `logfile` records the
            # traffic (the directory is created by the tmpfiles rule above).
            # The logfile name contains a timestamp of the moment the VM
            # starts: `virtualisation.qemu.options` strings are interpolated
            # verbatim into the generated bash runner script, so the shell
            # command substitution `$(date ...)` is evaluated every time the
            # runner is executed, giving each VM run its own log file.
            "-chardev stdio,id=vm-serial,mux=on,logfile=/var/log/vm-serial/${config.networking.hostName}-$(date +%Y%m%dT%H%M%S).log,logappend=on"
            "-object monitor-hmp,id=vm-monitor,chardev=vm-serial"
            "-serial chardev:vm-serial"

            # spice display + vdagent channel for clipboard sharing
            "-vga qxl"
            "-spice port=5901,addr=127.0.0.1,disable-ticketing=on" # with this, you can run `vm-view` (or `remote-viewer "spice://127.0.0.1:5901"`) to get a graphical interface
            "-device virtio-serial-pci"
            "-chardev spicevmc,id=vdagent0,name=vdagent"
            "-device virtserialport,chardev=vdagent0,name=com.redhat.spice.0"

            # a guest kernel panic terminates QEMU instead of hanging forever
            "-no-reboot"
          ];
        };
      };
    };

    environment = {
      persistence."/persist".directories = [
        "/var/lib/libvirt"
      ];

      systemPackages = [
        pkgs.virt-viewer # provides `remote-viewer`
        pkgs.sshpass # used by vm-ssh

        (pkgs.writeShellScriptBin "vm-view" ''
          exec ${pkgsLib.getExe' pkgs.virt-viewer "remote-viewer"} \
            "spice://127.0.0.1:5901" "$@"
        '')

        (pkgs.writeShellScriptBin "vm-ssh" ''
          exec ${pkgsLib.getExe pkgs.sshpass} -p ${pkgsLib.escapeShellArg testPassword} \
            ${pkgsLib.getExe pkgs.openssh} -p ${toString config.virtualisation.sshHostPort} \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR \
            ${config.virtualisation.sshUser}@127.0.0.1 "$@"
        '')
      ];
    };
  };
}