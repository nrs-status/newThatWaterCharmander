{
  lib,
  config,
  pkgs,
  ...
}:
let
  forgejoPort = 3000;
  cfg = config.services.forgejo;
  forgejoCmd = lib.getExe cfg.package;

  # accounts to ensure: the administrator followed by the regular users
  # (note: forgejo forbids an account literally named "admin", so the
  # administrator account is called wranHearst)
  adminUser = "wranHearst";
  normalUsers = [
    "sieyes"
    "plat2548"
    "soc7099"
  ];

  # password files for the accounts above, generated once by
  # forgejo-user-passwords.service (like garage's rpc-secret, see ../garage):
  # this repo's sops secrets file starts out empty and is filled at boot with
  # a host-derived key (see ../security), so random passwords cannot be
  # provisioned declaratively; they are generated on first boot instead
  passwordDir = "${cfg.stateDir}/user-passwords";

  # appended to the forgejo module's own preStart (which writes app.ini and
  # runs migrations): ensure the accounts exist. the || true mirrors the
  # snippet on https://wiki.nixos.org/wiki/Forgejo so an already existing
  # account does not fail the service
  ensureUser = user: isAdmin: ''
    ${forgejoCmd} admin user create \
      ${lib.optionalString isAdmin "--admin"} \
      --email "${user}@wranHearst.local" \
      --username ${user} \
      --must-change-password=false \
      --password "$(tr -d '\n' < ${passwordDir}/${user})" || true
  '';
in
{
  services.forgejo = {
    enable = true;

    # backed by the local postgresql server (see ../postgresql): the forgejo
    # module registers its own role/database via services.postgresql.ensureUsers
    database.type = "postgres";

    settings = {
      DEFAULT.APP_NAME = "forgejo";
      server = {
        DOMAIN = "wranHearst.local";
        ROOT_URL = "http://wranHearst.local:${toString forgejoPort}/";
        HTTP_ADDR = "0.0.0.0"; # reachable from the LAN
        HTTP_PORT = forgejoPort;
      };
      # accounts are provisioned by the admin (see preStart below), so
      # self-service registration is disabled
      service.DISABLE_REGISTRATION = true;
    };
  };

  # generate a random password file per account on first boot; skipped on
  # subsequent boots (ConditionPathExists) so passwords stay stable
  systemd.services.forgejo-user-passwords = {
    description = "generate random passwords for the forgejo accounts";
    wantedBy = [ "multi-user.target" ];
    before = [ "forgejo.service" ];
    unitConfig.ConditionPathExists = "!${passwordDir}";
    serviceConfig = {
      Type = "oneshot";
      UMask = "0077";
    };
    script = ''
      mkdir -p ${passwordDir}
      for user in ${adminUser} ${lib.concatStringsSep " " normalUsers}; do
        ${pkgs.openssl}/bin/openssl rand -base64 24 | tr -d '\n' > ${passwordDir}/$user
      done
      chown -R ${cfg.user}:${cfg.group} ${passwordDir}
    '';
  };

  systemd.services.forgejo = {
    after = [ "forgejo-user-passwords.service" ];
    wants = [ "forgejo-user-passwords.service" ];
    preStart = lib.mkAfter (
      ""
      + ensureUser adminUser true
      + lib.concatMapStrings (user: ensureUser user false) normalUsers
    );
  };

  networking.firewall.allowedTCPPorts = [ forgejoPort ];

  # wranHearst runs impermanence (root is wiped on reboot), so forgejo's state
  # (repositories, database, LFS objects, user-passwords) must be persisted
  # explicitly; declared here, inside the service module (same pattern as
  # ../garage, ../openBao, ../vaultWarden, ../kubernetes)
  environment.persistence."/persist".directories = [ cfg.stateDir ];

  # advertise the forgejo web UI over mDNS so it is discoverable on the
  # LAN as wranHearst.local (publishing itself is configured in ../avahi.nix)
  services.avahi.extraServiceFiles.forgejo = ''
    <?xml version="1.0" standalone='no'?><!--*-nxml-*-->
    <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
    <service-group>
      <name replace-wildcards="yes">%h forgejo</name>
      <service>
        <type>_http._tcp</type>
        <port>${toString forgejoPort}</port>
      </service>
    </service-group>
  '';
}
