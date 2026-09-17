# Virtual-machine variant of the wranHearst host, adapted into a self-contained
# test environment for wranHearst's sway configuration.
#
# Everything inside `virtualisation.vmVariant` is merged only into the machine
# produced by
#   nixos-rebuild build-vm --flake .#wranHearst
# (or `nix build .#nixosConfigurations.wranHearst.config.system.build.vm`); see
# nixos/modules/virtualisation/build-vm.nix, where `config.system.build.vm` is
# `config.virtualisation.vmVariant.system.build.vm`. The real host is therefore
# never affected by any of the overrides below. The handful of settings outside
# `virtualisation.vmVariant` are host-side conveniences needed to *reach* the
# VM (a SPICE viewer and an SSH wrapper); they are commented as such.
#
# Why a VM at all:
#   Sway is a Wayland compositor: exercising it means taking over a DRM/KMS
#   device, a seat and the whole session. Doing that on the host would fight
#   with the user's running sway (exactly the "interrupting my normal usage"
#   problem). Running the *same* generated sway + waybar configuration inside a
#   VM keeps all of it in a throwaway guest whose compositor, DRM device and
#   input seat the host window manager never sees.
#
# How the pieces fit together:
#   * the VM boots headless: qemu is started with `-display none`, so it never
#     maps a window of its own onto the host. The guest display is exported
#     through SPICE (127.0.0.1:5901) and, as a client-agnostic fallback, VNC
#     (127.0.0.1:5902).
#   * at any point the user can open a window showing the VM's compositor with
#     the host-side `wranHearst-vm-view` script (installed below), which just
#     launches `remote-viewer` against the SPICE port. Closing/opening it never
#     touches the guest sway session.
#   * sway starts automatically on tty1 (getty autologin + `loginShellInit`),
#     running the very same `programs.sway`/`programs.waybar` configuration the
#     host uses, so what is tested in the VM is what runs on the host.
#   * the agent (or the user) drives the guest over SSH (`wranHearst-vm-ssh`,
#     host port 2222, user `sieyes`): `swaymsg`, `grim`, `wlr-randr`, ... all
#     work against the running session because the relevant environment
#     variables are exported system-wide. An agent that normally runs on the
#     host thus never has to touch the host's compositor to test sway.
{ pkgsLib, pkgs, ... }:
let
  # the user the real host runs sway as; the VM runs the same user's session
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
    # ------------------------------------------------------------------
    # 1. host-specific settings that must not leak into a guest
    # ------------------------------------------------------------------
    boot = {
      # the VM runner boots the kernel directly, no boot loader (and the
      # systemd-boot/EFI setup from ./boot.nix makes no sense in a guest)
      loader.systemd-boot.enable = pkgsLib.mkForce false;
      loader.efi.canTouchEfiVariables = pkgsLib.mkForce false;

      # ./boot.nix loads the Intel iGPU driver and the host's KVM module. The
      # guest has neither device; keep the input drivers a virtual machine
      # actually needs (virtio keyboard + usb-tablet) and drop the rest.
      initrd.kernelModules = pkgsLib.mkForce [ "usbhid" "joydev" ];
      kernelModules = pkgsLib.mkForce [ "atkbd" "ctr" "loop" "tun" "uinput" ];
    };

    hardware.cpu.intel.updateMicrocode = pkgsLib.mkForce false;

    # ------------------------------------------------------------------
    # 2. users / login
    # ------------------------------------------------------------------
    services = {
      qemuGuest.enable = true; #allows host to query the vm
      spice-vdagentd.enable = true; #clipboard sync agent

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

    # keep the pre-existing extra account for serial-console poking around
    users.users.vm-user = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      initialPassword = "userpwd";
    };

    # start sway when logging in on tty1 (and *only* there: SSH sessions have a
    # /dev/pts/* tty and get an ordinary shell, which is what the agent uses).
    programs.bash.loginShellInit = ''
      if [ "$(tty)" = "/dev/tty1" ]; then
        # log the compositor's stderr so a sway that refuses to start can be
        # diagnosed over ssh (`cat /tmp/sway.log`); a crashing sway just
        # returns to agetty, which autologins and tries again, so iterative
        # debugging is painless.
        exec sway >/tmp/sway.log 2>&1
      fi

      # Ordinary (non-graphical) logins -- exactly what the agent uses over
      # ssh -- do not automatically inherit the compositor's WAYLAND_DISPLAY
      # (wl_display_add_socket_auto picks wayland-0/1/... at random, and the
      # compositor updates its *own* environment, which is invisible to other
      # sessions). Point clients such as grim/wlr-randr at the live socket so
      # they work without hardcoding a number.
      if [ -z "''${WAYLAND_DISPLAY:-}" ] && [ -d "/run/user/$(id -u)" ]; then
        sock=$(ls /run/user/$(id -u)/wayland-* 2>/dev/null | head -n1 || true)
        if [ -n "$sock" ]; then
          export WAYLAND_DISPLAY=$(basename "$sock")
        fi
      fi
    '';

    # ------------------------------------------------------------------
    # 3. sway / Wayland environment
    # ------------------------------------------------------------------
    # The VM's GPU (qxl, exported through SPICE) has no usable GL driver, so
    # tell wlroots to use the pixman software renderer -- the same workaround
    # nixpkgs' sway test uses. A fixed SWAYSOCK lets `swaymsg` work from the
    # SSH sessions the agent uses; `WAYLAND_DISPLAY` is discovered per login in
    # `loginShellInit` above (the compositor chooses its socket name itself).
    environment.variables = {
      # be explicit about the DRM/KMS backend: wlroots' auto-detection would
      # otherwise choose the nested Wayland backend whenever WAYLAND_DISPLAY
      # happens to be set in the environment, and fail before touching the GPU.
      WLR_BACKENDS = "drm";
      WLR_RENDERER = "pixman";
      # wlroots also refuses explicit software fallback unless asked; harmless
      # when pixman is selected explicitly, but keeps things working if a
      # future config removes the line above.
      WLR_RENDERER_ALLOW_SOFTWARE = "1";
      SWAYSOCK = "/tmp/sway-ipc.sock";
    };

    # tools a human or an agent needs to inspect/exercise the compositor.
    # (the host's ./sway module already pulls in grim, slurp, wl-clipboard,
    # mako, wev, remontoire, wvkbd, libnotify, ...).
    environment.systemPackages = with pkgs; [
      jq # rainbows over `swaymsg -t get_tree` etc.
      wayland-utils # `wayland-info`
      wlr-randr # inspect/change outputs
      wf-recorder # record the session while debugging
      wtype # synthesize input without a physical keyboard
      ydotool # synthesize input at the kernel level
      imagemagick # convert/inspect grim screenshots
    ];

    # ------------------------------------------------------------------
    # 4. resources
    # ------------------------------------------------------------------
    virtualisation = {
      diskSize = 30000;
      memorySize = 5120; # sway + the host's services + a browser
      cores = 4;
      graphics = true; #keeps console=tty0 console=ttyS0 available

      # expose sshd to the host so `wranHearst-vm-ssh` can reach the guest
      forwardPorts = [
        {
          from = "host";
          host.port = sshHostPort;
          guest.port = 22;
        }
      ];
      qemu.options = [
        "-display none" #no local window, graphical access goes through SPICE/VNC
        "-serial mon:stdio" #connects VM's emulated serial port to host user's terminal. This is what allows to get a login shell

        #spice display + vdagent channel for clipboard sharing
        "-vga qxl"
        "-spice port=5901,addr=127.0.0.1,disable-ticketing=on" #with this, you can run `wranHearst-vm-view` (or `remote-viewer "spice://127.0.0.1:5901"`) to get a graphical interface
        "-device virtio-serial-pci"
        "-chardev spicevmc,id=vdagent0,name=vdagent"
        "-device virtserialport,chardev=vdagent0,name=com.redhat.spice.0"

        # second, viewer-agnostic front end for the same display, for clients
        # without SPICE support (`remote-viewer vnc://127.0.0.1:5902`, or any
        # VNC client). display :2 is TCP port 5902; 5901 is taken by SPICE.
        "-vnc 127.0.0.1:2"
      ];
    };
  };

  # ------------------------------------------------------------------
  # host-side conveniences (these run on the host that launches the VM, not in
  # it, so they live outside virtualisation.vmVariant)
  # ------------------------------------------------------------------
  environment.systemPackages = [
    pkgs.virt-viewer # provides `remote-viewer`, used by wranHearst-vm-view
    pkgs.sshpass # used by wranHearst-vm-ssh
    wranHearstVmView
    wranHearstVmSsh
  ];
}
