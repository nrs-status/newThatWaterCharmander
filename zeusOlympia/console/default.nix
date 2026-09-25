{ pkgs, ... }:
let
  # about voice-input keymap:
  # keyd remaps rightalt to evdev F13 (keycode 183) so that voice-input
  # push-to-talk can be triggered system-wide (see
  # empTriageCan/louSelfHit-sofa/keyRemappings.nix). Sway receives the key as
  # xkb keycode 191 and binds it with `bindcode 191` (see
  # zeusOlympia/sway/swayDecl.nix), but the Linux virtual console does not see
  # evdev codes: it looks the keycode up in the kernel keymap. That keymap
  # (including the kernel's built-in defkeymap) has no entry for keycode 183,
  # so it resolves to VoidSymbol and the key produces *no* output at all in
  # the console -- tmux therefore never sees the F13 escape sequence and its
  # voice-input `User0` binding never fires.
  #
  # Bind keycode 183 to the F13 function key, which makes the console emit its
  # standard `\033[25~` (the terminfo kf13 string / kernel `string F13`), the
  # exact sequence templeArtemisEphesus/tmux matches through `user-keys`.
  #
  # The map is installed as a drop-in inside kbd's own keymap tree (rather than
  # passed to `console.keyMap` as an absolute store path): loadkeys resolves
  # an `include "..."` relative to the including keymap's directory and its
  # sibling `../include`, so the file has to live next to `us.map` in
  # `i386/qwerty`. `loadkeys` then finds it by name through the
  # `/etc/kbd/keymaps/**` search path, both when systemd-vconsole-setup runs
  # it at boot and when the initrd `optimizedKeymap` derivation compiles it.
  # This only affects the virtual console; sway keeps reading the raw keycode.
  voiceInputConsoleKeyMap = pkgs.runCommand "voice-input-console-keymap" { } ''
    mkdir -p $out/share/keymaps/i386/qwerty
    cat > $out/share/keymaps/i386/qwerty/voice-input.map <<'EOF'
    include "us.map"
    keycode 183 = F13
    EOF
  '';

  # A console bitmap font based on ter-128n (14x28, all 256 original glyphs
  # and unicode-table entries preserved) with three appended "status" glyphs
  # in the otherwise-unused slots 256..258 (PSF fonts may hold up to 512
  # glyphs), so the tmux status bar can display icons for RAM, CPU and
  # battery while inside the virtual console:
  #
  #   U+E100  CPU      (chip with pins)
  #   U+E101  RAM      (memory stick)
  #   U+E102  battery
  #
  # Private-use codepoints were chosen deliberately: the kernel console
  # resolves UTF-8 input through the font's unicode map, and tmux measures
  # private-use characters as single-width, so the status-bar layout stays
  # intact. The generation script (mkstatusfont.py) is also what documents
  # the pixel art of the three glyphs.
  statusGlyphsFont = pkgs.runCommand "ter-glyphs-consolefont"
    {
      nativeBuildInputs = [ pkgs.python3 ];
      terminus = pkgs.terminus_font;
    }
    ''
    mkdir -p $out/share/consolefonts
    python3 ${./mkstatusfont.py} $terminus/share/consolefonts/ter-128n.psf.gz $out/share/consolefonts/ter-glyphs-128n.psf
    gzip -n $out/share/consolefonts/ter-glyphs-128n.psf
  '';
in
{
  config.console = {
    # ter-glyphs-128n is ter-128n plus the status glyphs above, so the
    # console looks exactly as before while the icons become available.
    font = "ter-glyphs-128n";
    packages = [ pkgs.terminus_font statusGlyphsFont voiceInputConsoleKeyMap ];
    keyMap = "voice-input";
  };
}
