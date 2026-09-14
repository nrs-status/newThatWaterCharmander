{ pkgs, ... }:
let
  # credentials for the telegraf telemetry stream (see ../telegraf): the
  # agent hosts augtibcalcla / lanchamarcou insert into this database
  telegrafCredentials = import ./telegraf-credentials.nix;
  telegrafSchema =
    pkgs.writeText "telegraf-schema.sql" (builtins.readFile ./telegraf-schema.sql);
  docSchema = pkgs.writeText "doc-schema.sql" (builtins.readFile ./doc-schema.sql);
  # schema + ingest function for the JSON-lines span stream produced by
  # pi-json-span-processor (see newFrontArmToPlane/pi-json-span-processor/SPEC.md)
  piStreamSchema =
    pkgs.writeText "pi-stream-schema.sql" (builtins.readFile ./pi-stream-schema.sql);
  psql = "${pkgs.postgresql}/bin/psql";
in
{
  services.postgresql = {
    enable = true;

    # telegraf streams telemetry over the network from the agent hosts, so
    # listen on all interfaces and let the telegraf role authenticate with a
    # password (scram-sha-256) from private LAN ranges; the trailing default
    # rules appended by the module keep localhost peer/md5 access working
    enableTCPIP = true;
    authentication = ''
      host  ${telegrafCredentials.telegrafDatabase} ${telegrafCredentials.telegrafUser} 10.0.0.0/8       scram-sha-256
      host  ${telegrafCredentials.telegrafDatabase} ${telegrafCredentials.telegrafUser} 172.16.0.0/12   scram-sha-256
      host  ${telegrafCredentials.telegrafDatabase} ${telegrafCredentials.telegrafUser} 192.168.0.0/16  scram-sha-256
      host  ${telegrafCredentials.telegrafDatabase} ${telegrafCredentials.telegrafUser} ::1/128         scram-sha-256
    '';

    ensureDatabases = [
      "doc"
      "pi"
      telegrafCredentials.telegrafDatabase
    ];

    ensureUsers = [
      { name = "sieyes"; }
    ];
  };

  systemd.services.mypsql = {
    # NB: order after postgresql-setup.service, not postgresql.service:
    # postgresql.service reports readiness before ensureDatabases/ensureUsers
    # (now run by postgresql-setup.service) have created the databases, so a
    # fresh boot races and `psql -d doc` fails with 'database "doc" does not
    # exist'. postgresql-setup.service already requires/after postgresql.service.
    after = [ "postgresql-setup.service" ];
    requires = [ "postgresql-setup.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      User = "postgres";
      RemainAfterExit = true;
    };

    # applies the database schemas (including the pi-json-span-processor
    # ingestion schema) idempotently
    script = ''
      ${psql} -d doc -c 'ALTER DATABASE "doc" OWNER TO "sieyes"'
      ${psql} -d doc -f ${docSchema}
      ${psql} -d doc -c 'ALTER TABLE nodes OWNER TO "sieyes"'

      # pi-json-span-processor ingestion schema (idempotent)
      ${psql} -d pi -c 'ALTER DATABASE "pi" OWNER TO "sieyes"'
      ${psql} -d pi -f ${piStreamSchema}
      ${psql} -d pi -c 'ALTER TABLE pi_stream_spans OWNER TO "sieyes"'
      ${psql} -d pi -c 'ALTER TABLE pi_stream_sessions OWNER TO "sieyes"'
      ${psql} -d pi -c 'ALTER FUNCTION pi_stream_ingest(jsonb) OWNER TO "sieyes"'

      # telegraf telemetry ingestion schema (idempotent); the role is
      # cluster-wide so it is provisioned from the postgres database
      ${psql} -d postgres -c "DO \$\$ BEGIN IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${telegrafCredentials.telegrafUser}') THEN CREATE ROLE ${telegrafCredentials.telegrafUser}; END IF; END \$\$;"
      ${psql} -d postgres -c "ALTER ROLE ${telegrafCredentials.telegrafUser} WITH LOGIN PASSWORD '${telegrafCredentials.telegrafPassword}'"
      ${psql} -d ${telegrafCredentials.telegrafDatabase} -c "ALTER DATABASE \"${telegrafCredentials.telegrafDatabase}\" OWNER TO \"sieyes\""
      ${psql} -d ${telegrafCredentials.telegrafDatabase} -f ${telegrafSchema}
    '';
  };

  # the agent hosts need to reach the postgresql port over the LAN
  networking.firewall.allowedTCPPorts = [ 5432 ];
}
