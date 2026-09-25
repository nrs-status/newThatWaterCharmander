# VM test for the console status-glyph font (see ../../zeusOlympia/console
# and ../../zeusOlympia/console/mkstatusfont.py).
#
# Boots a VM whose console font is ter-glyphs-128n (ter-128n + three appended
# status glyphs) and verifies:
#
#   - the generated PSF font is installed in the system consolefonts
#   - the unicode map of the *loaded* console font (dumped with
#     `setfont -O`) really contains the three private-use codepoints
#     U+E100 (CPU), U+E101 (RAM) and U+E102 (battery) — i.e. the kernel
#     console will resolve those characters to the bitmap icons
#   - printing the codepoints to a VT renders them (screenshot of the plain
#     console: console-glyphs.png)
#   - a tmux status bar configured with the three icons renders in the
#     console (screenshot of tmux: console-tmux-glyphs.png), which is the
#     end goal: status-bar icons inside the console. tmux is attached to
#     tty2 through a systemd service with TTYPath so it is the foreground
#     process of that VT.
#
# The screenshots end up in the derivation output.
#
# run with: nix build .#checks.x86_64-linux.console-glyphs-vm-test
{
  pkgsLib,
  nixpkgsFlake,
}:
let
  pkgs = import nixpkgsFlake { system = "x86_64-linux"; };
in
pkgs.testers.runNixOSTest {
  name = "console-glyphs-vm-test";

  nodes.machine =
    { pkgs, ... }:
    {
      imports = [
        ../../zeusOlympia/console # the console configuration under test
      ];

      networking.hostName = "consoleGlyphsVm";

      environment.systemPackages = [ pkgs.tmux ];

      # minimal tmux config used only to demo the status bar with the
      # three glyphs (U+E100 CPU, U+E101 RAM, U+E102 battery — embedded as
      # literal UTF-8 below, right after each label)
      environment.etc."tmux-glyphs.conf".text = ''
        set -g status-interval 1
        # the default status-left-length is 10 cells, which silently
        # truncates the icon status line
        set -g status-left-length 100
        set -g status-style bg=colour235,fg=white
        set -g status-left "#[fg=colour39]CPU  #[default]#[fg=colour46]RAM  #[default]#[fg=colour220]BAT  #[default]"
        set -g status-right ""
        set -g window-status-format " "
        set -g window-status-current-format " "
      '';

      # attach a tmux client to tty2 (foreground of the VT, which is what
      # makes it actually draw there); started explicitly by the test
      systemd.services.tmux-glyphs-demo = {
        description = "tmux status-bar glyph demo on tty2";
        after = [ "multi-user.target" ];
        environment.TERM = "linux";
        serviceConfig = {
          Type = "simple";
          TTYPath = "/dev/tty2";
          TTYReset = "yes";
          StandardInput = "tty";
          StandardOutput = "tty";
          StandardError = "journal";
          WorkingDirectory = "/tmp";
          ExecStart = "${pkgs.tmux}/bin/tmux -f /etc/tmux-glyphs.conf new-session -A -s demo";
          Restart = "no";
        };
      };

      virtualisation = {
        graphics = false; # headless, but the VGA/virtio-gpu console exists
        memorySize = 2048;
        # virtio-gpu so the console runs on fbcon (like the real machine via
        # simpledrm); the plain VGA text console cannot display 14-wide fonts
        qemu.options = [ "-vga virtio" ];
      };
    };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    # console.packages are linked under /etc/kbd (see config/console.nix)
    font = "/etc/kbd/consolefonts/ter-glyphs-128n.psf.gz"

    # ---------------------------------------------------------------
    # the generated font is part of the system and the console font
    # (ter-128n + status glyphs) got loaded
    # ---------------------------------------------------------------
    machine.succeed(f"test -f {font}")
    machine.succeed("systemctl restart systemd-vconsole-setup.service")
    machine.succeed("systemctl is-active systemd-vconsole-setup.service")

    # ---------------------------------------------------------------
    # the unicode map of the *loaded* console font must map the three
    # private-use codepoints (E100/E101/E102 -> ee 84 80/81/82 in UTF-8)
    # ---------------------------------------------------------------
    machine.succeed("setfont -O /tmp/console.unimap")
    for utf8 in ("\\xee\\x84\\x80", "\\xee\\x84\\x81", "\\xee\\x84\\x82"):
        machine.succeed(
            f"grep -qF \"$(printf '{utf8}')\" /tmp/console.unimap"
        )

    # ---------------------------------------------------------------
    # render the glyphs on a real VT and take a screenshot
    # ---------------------------------------------------------------
    machine.execute("chvt 2")
    # chvt makes logind spawn getty@tty2 (agetty); it would steal the
    # terminal query replies of the tmux client below and restore canonical
    # tty mode, so stop it before attaching tmux (it does not respawn)
    machine.sleep(1)
    machine.succeed("systemctl stop getty@tty2 autovt@tty2 2>/dev/null; true")
    machine.sleep(1)
    machine.execute(
        "! systemctl is-active --quiet getty@tty2 && ! systemctl is-active --quiet autovt@tty2"
    )
    machine.succeed(
        # write to tty2: header + the three icons
        "printf '\\nter-glyphs-128n status glyphs:\\n"
        "CPU \\xee\\x84\\x80   RAM \\xee\\x84\\x81   BAT \\xee\\x84\\x82\\n' > /dev/tty2"
    )
    machine.sleep(2)
    machine.screenshot("console-glyphs.png")

    # console-level repro: write the exact byte sequence tmux uses for the
    # status bar (see local capture) straight to the VT
    machine.succeed(
        "printf '\\033[38;5;39m\\033[48;5;235m\\n"
        "CPU \\xee\\x84\\x80 \\033[38;5;46mRAM \\xee\\x84\\x81 "
        "\\033[38;5;220mBAT \\xee\\x84\\x82 END\\n' > /dev/tty2"
    )
    machine.sleep(1)
    machine.screenshot("console-barbytes.png")

    # ---------------------------------------------------------------
    # the actual goal: a tmux status bar showing the icons in the console
    # ---------------------------------------------------------------
    machine.succeed("systemctl start tmux-glyphs-demo.service")
    machine.succeed("systemctl is-active tmux-glyphs-demo.service")
    machine.sleep(3)
    print("CLIENTS:", machine.execute("tmux list-clients || true")[1])
    machine.screenshot("console-tmux-glyphs.png")

    # ---------------------------------------------------------------
    # capture the raw bytes tmux sends to a client terminal, to verify
    # that the client really emits all three glyphs (BAT = ee 84 82)
    # ---------------------------------------------------------------
    machine.execute(
        "TERM=linux script -q -c "
        "\"sh -c 'stty rows 28 cols 91; exec tmux attach -t demo'\" "
        "/tmp/cap.txt >/dev/null 2>&1 &"
    )
    machine.sleep(3)
    machine.execute("pkill -f 'tmux attach' || true")
    machine.sleep(1)
    print(
        "GLYPH BYTE COUNTS EMITTED BY A SECOND TMUX CLIENT (cpu, ram, bat):",
        machine.execute(
            "for g in '\\xee\\x84\\x80' '\\xee\\x84\\x81' '\\xee\\x84\\x82'; do "
            "grep -a -o \"$(printf %s \"$g\")\" /tmp/cap.txt 2>/dev/null | wc -l; done"
        )[1],
    )
  '';
}
