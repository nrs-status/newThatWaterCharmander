{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [ pavucontrol pulseaudio ];

  services = {
    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };
    pulseaudio.enable = false;
  };

}

# llm note:
# A quick note: services.pipewire.enable and hardware.pulseaudio.enable are typically mutually exclusive in NixOS — PipeWire can replace PulseAudio entirely. If you actually  
#  want PipeWire with PulseAudio compatibility (the more common setup), you'd replace hardware.pulseaudio.enable = true with services.pipewire.pulse.enable = true and drop the 
#  standalone pulseaudio package.
