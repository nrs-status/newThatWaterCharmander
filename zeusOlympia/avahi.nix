{
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    # publish the host's own mDNS address records (default is false): without
    # this, wranHearst is not resolvable as wranHearst.local from the agent
    # hosts that stream telemetry to its postgresql server (see ./postgresql)
    publish.addresses = true;
  };
}
