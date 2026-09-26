{
  config,
  pkgs,
  ...
}:
let
  xandikosPort = 8330;
in
{
  services.xandikos = {
    enable = true;
    package = pkgs.xandikos;

    # reachable from the LAN (and from the headscale tailnet, see ../headscale)
    address = "0.0.0.0";
    port = xandikosPort;

    # bootstrap a usable server on first start: xandikos creates the data
    # directory layout (--autocreate, implied by --defaults) and the default
    # calendar + address book for the current user principal. the principal
    # path must start with "/" (xandikos validates relpath formats strictly
    # and crashes on startup otherwise). NB: xandikos 0.4.x has no built-in
    # HTTP authentication for plain HTTP; write access is restricted at the
    # network level (LAN/tailnet only, see the firewall setting below). to
    # add authentication, either put a reverse proxy in front (the upstream
    # module's services.xandikos.nginx option) or switch to
    # extraOptions = [ "--autocert" "--htpasswd <file>" ] for self-signed
    # HTTPS with basic auth
    extraOptions = [
      "--defaults"
      "--current-user-principal /sieyes/"
    ];
  };

  # the upstream module runs xandikos with DynamicUser=true and
  # StateDirectory=xandikos, so the real state directory (calendars and
  # address books, stored as git repositories) is /var/lib/private/xandikos
  # (systemd creates /var/lib/xandikos as a symlink at service start).
  # wranHearst runs impermanence (root is wiped on reboot), so the state must
  # be persisted explicitly; the parent /var/lib/private is already persisted
  # by the garage module (see ../garage)
  environment.persistence."/persist".directories = [
    { directory = "/var/lib/private/xandikos"; mode = "0700"; }
  ];

  networking.firewall.allowedTCPPorts = [ xandikosPort ];

  # xandikos is reachable over the headscale tailnet (see ../headscale) at
  # wranHearst.tailnet.internal:${toString xandikosPort}; the same pattern as
  # ../forgejo, ../garage, ../harmonia
}
