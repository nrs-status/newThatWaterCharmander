# SUMMARY — console bitmap font with status glyphs (tmux status-bar icons)

Goal: extend the console configuration (`zeusOlympia/console`, i.e.
`zeusOlympia/console/default.nix`) with a console bitmap font that carries
status glyphs (CPU, RAM, battery) so that a tmux status bar can display icons
while inside the virtual console — and test it, including a VM run with
screenshots.

## What was changed

- **`zeusOlympia/console/mkstatusfont.py`**: generator for the font. It reads
  Terminus `ter-128n.psf.gz` (14x28 PSF2, 256 glyphs, unicode table), copies
  all 256 original glyphs and their unicode-table entries verbatim, appends
  three hand-drawn 14x28 pixel glyphs into the otherwise unused PSF slots
  256–258 (PSF fonts may hold up to 512 glyphs), extends the PSF2 unicode
  table accordingly (one entry per slot, empty slots padded with `0xFF` —
  kbd rejects a "short" table otherwise) and writes the result as PSF2:

  | slot | codepoint | glyph |
  |------|-----------|-------|
  | 256  | U+E100    | CPU (chip with pins) |
  | 257  | U+E101    | RAM (memory stick) |
  | 258  | U+E102    | battery |

  Private-use codepoints were chosen on purpose: the kernel console resolves
  UTF-8 input through the font's unicode map, and tmux measures private-use
  characters as single width, so the status-bar layout stays intact.

- **`zeusOlympia/console/default.nix`** (moved from `zeusOlympia/console.nix`
  so that all console-related files live together in
  `zeusOlympia/console/`; the flake's module loader keys it as `console`
  exactly as before): added a `statusGlyphsFont` derivation
  (`pkgs.runCommand`) that runs `mkstatusfont.py` and installs
  `ter-glyphs-128n.psf.gz` into `share/consolefonts/`; `console.font` is now
  `ter-glyphs-128n` (identical appearance to the previous `ter-128n`, plus
  the three icons). The voice-input keymap setup is untouched.

- **`kaounSlidesTotem/console-glyphs-test/default.nix`** (new): VM test
  `.#checks.x86_64-linux.console-glyphs-vm-test` built with
  `pkgs.testers.runNixOSTest`; it imports `zeusOlympia/console`
  unchanged, runs the console on virtio-gpu/fbcon (like the real machine via
  simpledrm — the plain VGA text console cannot display 14-pixel-wide fonts)
  and verifies:
  - the generated font is installed and `systemd-vconsole-setup` loads it;
  - `setfont -O` (the unicode map of the *loaded* console font) contains
    U+E100/U+E101/U+E102;
  - printing the codepoints to a VT renders the icons (screenshot);
  - writing the exact escape-sequence/glyph byte stream of a tmux status bar
    straight to the VT renders it in colour (screenshot, console-level repro);
  - a real tmux status bar configured with the three icons renders in the
    console (screenshot). tmux is attached to tty2 through a systemd service
    with `TTYPath` so it is the foreground process of that VT; the test stops
    the getty that logind spawns on `chvt` first (it would steal the tmux
    client's terminal-query replies);
  - demo pitfall documented in the test: tmux's default
    `status-left-length` (10 cells) silently truncated the icon status line.

- **`flake.nix`**: registered the test as
  `checks.x86_64-linux.console-glyphs-vm-test`.

- **`kaounSlidesTotem/console-glyphs-test/screenshots/`** (new): the
  screenshots produced by the VM test (also present in the derivation
  output of the check):
  - `console-glyphs.png` — plain console (tty2, getty prompt) showing
    `CPU ⛁   RAM ⛁   BAT ⛁` with all three bitmap icons;
  - `console-barbytes.png` — the tmux status-bar byte stream (with
    256-colour SGR sequences) written directly to the VT, rendering
    `CPU ⛁ RAM ⛁ BAT ⛁ END` in colour;
  - `console-tmux-glyphs.png` — a live tmux with its status bar showing
    `CPU [chip] RAM [stick] BAT [battery]` inside the console.

## Steps undertaken

1. Inspected the console configuration (`zeusOlympia/console.nix`, later
   moved to `zeusOlympia/console/default.nix`) and the repo/flake structure;
   the
   existing console font is Terminus `ter-128n` (PSF2, 14x28, 256 glyphs).
2. Wrote `console/mkstatusfont.py` to extend that PSF2 font with three status glyphs
   (pixel art defined in the script) and an extended unicode table.
3. Generated the font locally and rendered a PNG preview of the new glyphs to
   check the pixel art; iterated on the RAM/battery drawings.
4. Verified with kbd's `psfgettable` that the table parses and maps
   U+E100/U+E101/U+E102 to slots 256–258. (First attempt failed with
   "short unicode table" — fixed by padding every glyph slot with an entry.)
5. Wired the font into the console module as a `runCommand` derivation providing
   `share/consolefonts/ter-glyphs-128n.psf.gz`, and switched `console.font`
   to it; verified the derivation builds and that the first 256 glyphs are
   byte-identical to the original ter-128n.
6. Wrote the VM test, registered it in `flake.nix`, and iterated:
   - fixed the in-VM font path (`/etc/kbd/consolefonts/...`);
   - fixed the "short unicode table" rejection by `setfont`;
   - made tmux actually draw on tty2 (systemd service with `TTYPath`;
     a backgrounded `tmux attach` never becomes the VT foreground process);
   - stopped the getty spawned by logind on `chvt` (it stole the tmux
     client's DSR replies and broke the attach);
   - diagnosed the "truncated after RAM" status bar with a console-level
     repro (proved the console renders the full coloured glyph stream) and
     found the real cause: tmux's default `status-left-length = 10`;
     set it to 100 in the demo config.
7. Final `nix build .#checks.x86_64-linux.console-glyphs-vm-test` run passes
   and produces the three screenshots (copied into the repo, untracked).
8. Verified all flake hosts (`wranHearst`, `wranHearst-minimal`,
   `wH-full`) still evaluate with the new console module.
9. Moved the console configuration into its own directory
   (`zeusOlympia/console.nix` -> `zeusOlympia/console/default.nix`,
   `zeusOlympia/mkstatusfont.py` -> `zeusOlympia/console/mkstatusfont.py`),
   updated the import in the VM test and re-ran all tests to confirm
   everything still works.

## How to use the icons

Inside the console (any VT), the characters U+E100/U+E101/U+E102 render as
CPU/RAM/battery icons, e.g. in a tmux status bar:

    set -g status-left-length 100
    set -g status-left "CPU \uE100  RAM \uE101  BAT \uE102 "

(embed the literal UTF-8 characters, or printf them:
`printf '\xee\x84\x80'` = CPU, `\xee\x84\x81` = RAM, `\xee\x84\x82` = BAT).
Remember that tmux truncates `status-left` at `status-left-length` (10 by
default).

## Running the test

    nix build .#checks.x86_64-linux.console-glyphs-vm-test

The screenshots are written into the derivation output
(`result/console-*.png`).

Nothing was committed; all changes are working-tree only.
