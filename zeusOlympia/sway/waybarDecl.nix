{ pkgs }:
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
                car = "<U+F010B>";
                handsfree = "<U+F02CE>";
                hdmi = "<U+F0841>";
                headphones = "<U+F02CB>";
                headset = "<U+F02CE>";
                hifi = "<U+F05DC>";
                phone = "<U+F03F6>";
                portable = "<U+F03F6>";
                default = ["<U+F057F>" "<U+F0580>" "<U+F057E>"];
              };
              format = "{icon}{volume:3}%";
              format-bluetooth = "{icon}<U+F00AF>{volume:3}%";
              format-muted = "<U+F075F>{volume:3}%";
            };
            backlight = {
              format = "{icon}";
              format-icons = ["<U+F06E9>" "<U+F1A4E>" "<U+F1A4F>" "<U+F1A50>" "<U+F1A51>" "<U+F1A52>" "<U+F1A53>" "<U+F1A54>" "<U+F1A55>" "<U+F1A56>" "<U+F06E8>"];
              on-scroll-up = "${pkgs.brightnessctl} set +10%";
              on-scroll-down = "${pkgs.brightnessctl} set 10%-";
              on-click-right = "${pkgs.brightnessctl} set 100%";
              on-click-middle = "${pkgs.brightnessctl} set 0%";
            };
            #"custom/keyboard-layout"
            network = {
              format-wifi = "{icon}";
              interval = 20;
              format-ethernet = "<U+F0200>";
              format-linked = "<U+F0337>";
              format-icons = ["<U+F092B>" "<U+F092F>" "<U+F091F>" "<U+F0922>" "<U+F0925>" "<U+F0928>"];
              format-disconnected = "<U+F092E>";
              on-click = "${pkgs.networkmanagerapplet}/bin/nm-connection-editor";
              tooltip-format = "<U+F0A5F>{ipaddr} <U+F0002>{essid} {frequency} {icon}{signalStrength} <U+F0552>{bandwidthUpBits} 
<U+F01DA>{bandwidthDownBits}";
            };
            bluetooth = {
              format-icons = {
                disabled = "<U+F00B2>";
                enabled = "<U+F00AF>";
              };
              format = "{icon}";
              on-click = "${pkgs.blueman}/bin/blueman-manager";
              on-click-right = "${pkgs.util-linux}/bin/rfkill toggle bluetooth";
               };
            battery = {
              format = "{icon}";
              rotate = 270;
              # TODO set different icons when charging (currently broken?)
              format-icons = ["<U+F10CD>" "<U+F007A>" "<U+F007B>" "<U+F007C>" "<U+F007D>" "<U+F007E>" "<U+F007F>" "<U+F0080>" "<U+F0081>" "<U+F0082>" "<U+F0079>"];
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
                activated = "<U+F0176>";
                deactivated = "<U+F0FAA>";
              };
            };
            clock = {
              interval = 1;
              timezone = "America/Argentina/Buenos_Aires";
              format = "<U+F0150>{:%T}";
              tooltip-format = "{:%F}";
            };
          }
        ];
}
