{ pkgsLib, pkgs }:
{
        settings = [
          {
            #settings for hide
            swaybar_command = "waybar";
            ipc = "true";
            mode = "hide";
            modifier = "Mod4";
            hidden_state = "hide";
            #start_hidden = "true";
            layer = "top";
            tray_output = "primary";

            position = "top";
            height = 35;
            modules-left = ["sway/workspaces" "sway/mode" "idle_inhibitor"];
            modules-right =
               ["backlight" "battery" "network" "pulseaudio" "clock"];
            "sway/workspaces".numeric-first = true;
            pulseaudio = {
              on-click = "${pkgs.pavucontrol}/bin/pavucontrol";
              on-click-right = "${pkgs.pulseaudio}/bin/pactl set-sink-mute 0 toggle";
              format-icons = {
                # TODO bluetooth + muted icons? (needs support upstream?)
                car = "󰄋";
                handsfree = "󰋎";
                hdmi = "󰡁";
                headphones = "󰋋";
                headset = "󰋎";
                hifi = "󰗜";
                phone = "󰏶";
                portable = "󰏶";
                default = ["󰕿" "󰖀" "󰕾"];
              };
              format = "{icon}{volume:3}%";
              format-bluetooth = "{icon}󰂯{volume:3}%";
              format-muted = "󰝟{volume:3}%";
            };
            backlight = {
              format = "{icon}";
              format-icons = ["󰛩" "󱩎" "󱩏" "󱩐" "󱩑" "󱩒" "󱩓" "󱩔" "󱩕" "󱩖" "󰛨"];
              on-scroll-up = "${pkgsLib.getExe pkgs.brightnessctl} set +10%";
              on-scroll-down = "${pkgsLib.getExe pkgs.brightnessctl} set 10%-";
              on-click-right = "${pkgsLib.getExe pkgs.brightnessctl} set 100%";
              on-click-middle = "${pkgsLib.getExe pkgs.brightnessctl} set 0%";
            };
            #"custom/keyboard-layout"
            network = {
              format-wifi = "{icon}";
              interval = 20;
              format-ethernet = "󰈀";
              format-linked = "󰌷";
              format-icons = ["󰤫" "󰤯" "󰤟" "󰤢" "󰤥" "󰤨"];
              format-disconnected = "󰤮";
              on-click = "${pkgs.networkmanagerapplet}/bin/nm-connection-editor";
              tooltip-format = "󰩟{ipaddr} 󰀂{essid} {frequency} {icon}{signalStrength} 󰕒{bandwidthUpBits} 
󰇚{bandwidthDownBits}";
            };
            bluetooth = {
              format-icons = {
                disabled = "󰂲";
                enabled = "󰂯";
              };
              format = "{icon}";
              on-click = "${pkgs.blueman}/bin/blueman-manager";
              on-click-right = "${pkgs.util-linux}/bin/rfkill toggle bluetooth";
               };
            battery = {
              format = "{icon}";
              rotate = 270;
              # TODO set different icons when charging (currently broken?)
              format-icons = ["󱃍" "󰁺" "󰁻" "󰁼" "󰁽" "󰁾" "󰁿" "󰂀" "󰂁" "󰂂" "󰁹"];
              states = {
                critical = 10;
                warning = 30;
              };
              tooltip-format = "{timeTo} - {capacity}%";
              tooltip = "true";
            };
            idle_inhibitor = {
              format = "{icon}";
              format-icons = {
                activated = "󰅶";
                deactivated = "󰾪";
              };
            };
            clock = {
              interval = 1;
              timezone = "America/Argentina/Buenos_Aires";
              format = "󰅐{:%T}";
              tooltip-format = "{:%F}";
            };
          }
        ];
}
