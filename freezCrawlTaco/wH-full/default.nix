{
  hostModules,
  localLib,
  pkgs,
  ...
}:
{
  imports = [
    hostModules.wranHearst
    (localLib.mkDirectoryImporterModule ./.)
  ];

  virtualisation.vmVariant = {

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
    # sway / Wayland environment
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
      # NOTE: when WLR_BACKENDS is set, wlroots loads *only* the listed backends,
      # and input lives in the separate "libinput" backend. Listing just "drm"
      # gives a compositor with a working display but zero input devices (no
      # clicks, no keyboard) -- including from VNC/SPICE -- so both are listed.
      WLR_BACKENDS = "drm,libinput";
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

    virtualisation = {
      diskSize = 30000;
      memorySize = 8000; # sway + the host's services + a browser
      cores = 4;
      graphics = true; # keeps console=tty0 console=ttyS0 available

      qemu.options = [
        # second, viewer-agnostic front end for the display, for clients
        # without SPICE support (`remote-viewer vnc://127.0.0.1:5902`, or any
        # VNC client). display :2 is TCP port 5902; 5901 is taken by SPICE.
        "-vnc 127.0.0.1:2"
      ];
    };

  };
}
