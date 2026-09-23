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
in
{
  config.console = {
    font = "ter-128n";
    packages = [ pkgs.terminus_font voiceInputConsoleKeyMap ];
    keyMap = "voice-input";
  };
}
