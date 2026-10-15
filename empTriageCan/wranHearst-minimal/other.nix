{
  system.stateVersion = "26.11";

  #vr screen share

  #9757 is for WiVRn
  # ports closed off (commented out); uncomment to use WiVRn again
  # networking.firewall.allowedTCPPorts = [ 9757 ];
  networking.firewall.allowedUDPPorts = [ 5353 ]; #5353 is for avhi

}
