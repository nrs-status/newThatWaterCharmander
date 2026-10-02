{
  system.stateVersion = "26.11";

  #vr screen share

  #9757 is for WiVRn
  networking.firewall.allowedTCPPorts = [ 9757 ];
  networking.firewall.allowedUDPPorts = [ 5353 9757 ]; #5353 is for avhi

}
