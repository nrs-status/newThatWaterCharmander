{
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      # addresses alone only publish A/AAAA records (so *.local resolves);
      # without a service announcement the host never shows up in avahi-browse
      workstation = true;
    };
  };
}
