let gruvbox = import ./gruvboxColors.nix;
in ''
   * {
      border: none;
      border-radius: 0;
      font-family: Iosevka;
      font-size: 24px;
      min-height: 0;
  }

  window#waybar {
      background-color: rgba(40, 40, 40, 0.9);
      border-bottom: 3px solid rgba(213, 196, 161, 0.9);
      color: ${gruvbox.dark.fg};
      transition-property: background-color;
      transition-duration: .5s;
  }

  window#waybar.hidden {
      opacity: 0.2;
  }

  #workspaces button {
      background-color: transparent;
      color: ${gruvbox.dark.fg};
      box-shadow: inset 0 -3px transparent;
  }

  #workspaces button:hover {
      background: rgba(40, 40, 40, 0.9);
      box-shadow: inset 0 -3px rgba(235, 219, 178, 0.9);
  }

  #workspaces button.focused {
      background-color: ${gruvbox.dark.bg3};
      box-shadow: inset 0 -3px ${gruvbox.light.bg0_h};
  }

  #workspaces button.urgent {
      background-color: ${gruvbox.dark.red.bright};
  }

  #mode {
      background-color: ${gruvbox.dark.bg1};
      border-bottom: 3px solid ${gruvbox.dark.fg};
  }

  #clock,
  #battery,
  #bluetooth,
  #cpu,
  #custom-memory,
  #disk,
  #temperature,
  #backlight,
  #network,
  #pulseaudio,
  #custom-media,
  #tray,
  #mode,
  #idle_inhibitor,
  #window,
  #workspaces {
      margin: 0 4px;
      padding: 0 10px;
  }

  #window,
  #workspaces {
      margin: 0 4px;
  }

  #clock {
      background-color: ${gruvbox.light.purple.bright};
  }

  #battery {
      background-color: ${gruvbox.light.yellow.bright};
  }

  #battery.charging, #battery.plugged {
      color: ${gruvbox.dark.fg};
      background-color: ${gruvbox.light.green.bright};
  }

  @keyframes blink {
      to {
          background-color: ${gruvbox.dark.yellow.normal};
          color: ${gruvbox.dark.fg};
      }
  }

  #battery.critical:not(.charging) {
      background-color: ${gruvbox.dark.red.bright};
      color: ${gruvbox.dark.fg};
      animation-name: blink;
      animation-duration: 1s;
      animation-timing-function: linear;
      animation-iteration-count: infinite;
      animation-direction: alternate;
  }

  label:focus {
      background-color: ${gruvbox.dark.bg};
  }

  #cpu {
      background-color: ${gruvbox.dark.orange.normal};
  }

  #custom-memory {
      background-color: ${gruvbox.dark.cyan.normal};
  }

  #disk {
    background-color: ${gruvbox.light.cyan.bright};
  }

  #backlight {
      background-color: ${gruvbox.dark.yellow.normal};
  }

  #bluetooth {
      background-color: ${gruvbox.light.blue.bright};
  }

  #network {
      background-color: ${gruvbox.dark.blue.normal};
  }

  #network.disconnected {
      background-color: ${gruvbox.dark.red.bright};
  }

  #pulseaudio {
      background-color: ${gruvbox.dark.purple.normal};
  }

  #pulseaudio.muted {
      background-color: ${gruvbox.dark.gray};
  }

  #temperature {
      background-color: ${gruvbox.dark.orange.bright};
  }

  #temperature.critical {
      background-color: ${gruvbox.dark.red.bright};
  }

  #idle_inhibitor {
      background-color: ${gruvbox.dark.gray};
  }

  #idle_inhibitor.activated {
      background-color: ${gruvbox.light.bg};
      color: ${gruvbox.light.fg};
  }

  #mpd {
      background-color: ${gruvbox.dark.purple.bright};
      color: ${gruvbox.light.fg};
  }

  #mpd.disconnected {
      background-color: rgba(0, 0, 0, 0);
  }

  #mpd.stopped {
      background-color: rgba(0, 0, 0, 0);
  }

  #mpd.paused {
      background-color: ${gruvbox.dark.gray};
      color: ${gruvbox.dark.fg};
  }

''
