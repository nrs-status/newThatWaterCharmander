{
  networking = {
    networkmanager.enable = true;
    hostName = "augtibcalcla";
    #DHCP is handled by NetworkManager; setting useDHCP here conflicts with
    #the value NetworkManager's module assigns to it
    useDHCP = false;
  };
}
