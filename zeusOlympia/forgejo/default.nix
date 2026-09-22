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
      --email "${user}@${config.tailnet.baseDomain}" \
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
        DOMAIN = config.tailnet.magicFqdn;
        ROOT_URL = "http://${config.tailnet.magicFqdn}:${toString forgejoPort}/";
        HTTP_ADDR = "0.0.0.0"; # reachable from the LAN
        HTTP_PORT = forgejoPort;
      };
      # accounts are provisioned by the admin (see preStart below), so
      # self-service registration is disabled
      service.DISABLE_REGISTRATION = true;
    };
  };

  # generate a random password file per account on first boot; skipped on
  # subsequent boots (ConditionPathExists) so passwords stay stable.
  # unprivileged: it runs as the forgejo user, not root - the forgejo module's
  # tmpfiles rules create cfg.stateDir (0750, owned by cfg.user:cfg.group)
  # before any multi-user.target unit, so this unit can create the password
  # dir itself and the generated files are already forgejo-owned; the
  # previous root-run variant's trailing chown is therefore unnecessary
  # (and would fail) here
  systemd.services.forgejo-user-passwords = {
    description = "generate random passwords for the forgejo accounts";
    wantedBy = [ "multi-user.target" ];
    before = [ "forgejo.service" ];
    unitConfig.ConditionPathExists = "!${passwordDir}";
    serviceConfig = {
      Type = "oneshot";
      UMask = "0077";
      User = cfg.user;
      Group = cfg.group;
    };
    script = ''
      mkdir -p ${passwordDir}
      for user in ${adminUser} ${lib.concatStringsSep " " normalUsers}; do
        ${pkgs.openssl}/bin/openssl rand -base64 24 | tr -d '\n' > ${passwordDir}/$user
      done
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

  # expose the forgejo CLI outside the systemd unit. the service locates its
  # config only through the unit's own environment (FORGEJO_WORK_DIR /
  # FORGEJO_CUSTOM, set by the nixpkgs module), which `sudo -u forgejo`
  # strips: without them forgejo resolves its work path to the caller's cwd,
  # finds no app.ini, and "forgejo admin user list" dies with
  # "Unable to load config file for a installed Forgejo instance". this
  # wrapper supplies the same environment and the real config path, so
  #   sudo -u forgejo forgejo admin user list
  # works from any shell. it must still run as the forgejo user (the state
  # dir and custom/conf are 0750 root:forgejo), exactly like the service.
  # the service itself is unaffected: the unit ExecStart/ExecStartPre point
  # straight at the unwrapped store-path binary.
  environment.systemPackages = lib.singleton (pkgs.writeShellScriptBin "forgejo" ''
    exec env \
      FORGEJO_WORK_DIR=${cfg.stateDir} \
      FORGEJO_CUSTOM=${cfg.customDir} \
      ${lib.getExe cfg.package} --config ${cfg.customDir}/conf/app.ini "$@"
  '');

  # wranHearst runs impermanence (root is wiped on reboot), so forgejo's state
  # (repositories, database, LFS objects, user-passwords) must be persisted
  # explicitly; declared here, inside the service module (same pattern as
  # ../garage, ../openBao, ../vaultWarden, ../kubernetes)
  environment.persistence."/persist".directories = [ cfg.stateDir ];

  # advertise the forgejo web UI over the headscale tailnet (see
  # ../headscale): it is reachable at ${config.tailnet.magicFqdn}:${toString forgejoPort}
  # from every enrolled host (augtibcalcla, lanchamarcou) via MagicDNS. the
  # old mDNS/Avahi advertisement (_http._tcp via services.avahi) was removed.
}
