{
  networking = {
    networkmanager.enable = true;
    hostName = "augtibcalcla";
    #DHCP is handled by NetworkManager; setting useDHCP here conflicts with
    #the value NetworkManager's module assigns to it
    useDHCP = false;
  };

  services.avahi.publish = {
    enable = true;
    addresses = true; # publishes its current IPv4/IPv6  as A/AAAA records
    domain = true;
  };

}
