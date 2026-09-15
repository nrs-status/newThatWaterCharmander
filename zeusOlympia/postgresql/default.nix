{ pkgs, ... }:
let
  # credentials for the telegraf telemetry stream (see ../telegraf): the
  # agent hosts augtibcalcla / lanchamarcou insert into this database
  telegrafCredentials = import ./telegraf-credentials.nix;
  telegrafSchema =
    pkgs.writeText "telegraf-schema.sql" (builtins.readFile ./telegraf-schema.sql);
  # credentials + schema for the arunman run-tracking stream (see the
  # arunman SPEC.md in the frontArmToPlane flake): the tool records every pi
  # microvm run in the `run' table of the `arunman' database
  arunmanCredentials = import ./arunman-credentials.nix;
  arunmanSchema =
    pkgs.writeText "arunman-schema.sql" (builtins.readFile ./arunman-schema.sql);
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
      host  ${arunmanCredentials.arunmanDatabase} ${arunmanCredentials.arunmanUser} 10.0.0.0/8       scram-sha-256
      host  ${arunmanCredentials.arunmanDatabase} ${arunmanCredentials.arunmanUser} 172.16.0.0/12   scram-sha-256
      host  ${arunmanCredentials.arunmanDatabase} ${arunmanCredentials.arunmanUser} 192.168.0.0/16  scram-sha-256
      host  ${arunmanCredentials.arunmanDatabase} ${arunmanCredentials.arunmanUser} ::1/128         scram-sha-256
    '';

    ensureDatabases = [
      "doc"
      "pi"
      telegrafCredentials.telegrafDatabase
      arunmanCredentials.arunmanDatabase
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

      # arunman run-tracking ingestion schema (idempotent); the role is
      # cluster-wide so it is provisioned from the postgres database
      ${psql} -d postgres -c "DO \$\$ BEGIN IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${arunmanCredentials.arunmanUser}') THEN CREATE ROLE ${arunmanCredentials.arunmanUser}; END IF; END \$\$;"
      ${psql} -d postgres -c "ALTER ROLE ${arunmanCredentials.arunmanUser} WITH LOGIN PASSWORD '${arunmanCredentials.arunmanPassword}'"
      ${psql} -d ${arunmanCredentials.arunmanDatabase} -c "ALTER DATABASE \"${arunmanCredentials.arunmanDatabase}\" OWNER TO \"sieyes\""
      ${psql} -d ${arunmanCredentials.arunmanDatabase} -f ${arunmanSchema}
      ${psql} -d ${arunmanCredentials.arunmanDatabase} -c 'ALTER TABLE run OWNER TO "sieyes"'
      ${psql} -d ${arunmanCredentials.arunmanDatabase} -c "GRANT CONNECT ON DATABASE \"${arunmanCredentials.arunmanDatabase}\" TO ${arunmanCredentials.arunmanUser}"
      # the role only ingests run entries: DML on the `run' table (INSERT on
      # the serial id needs USAGE on its sequence), no DDL. CREATE on the
      # public schema is still required because arunman always runs
      # `CREATE TABLE IF NOT EXISTS run ...' on connect (no-op here, but
      # postgres >= 15 checks the schema privilege before the existence
      # notice), so the role must not be denied it.
      ${psql} -d ${arunmanCredentials.arunmanDatabase} -c "GRANT USAGE, CREATE ON SCHEMA public TO ${arunmanCredentials.arunmanUser}"
      ${psql} -d ${arunmanCredentials.arunmanDatabase} -c "GRANT SELECT, INSERT, UPDATE, DELETE ON run TO ${arunmanCredentials.arunmanUser}"
      ${psql} -d ${arunmanCredentials.arunmanDatabase} -c "GRANT USAGE, SELECT ON SEQUENCE run_id_seq TO ${arunmanCredentials.arunmanUser}"
    '';
  };

  # wranHearst runs impermanence (root is wiped on reboot), so the postgresql
  # data directory must be persisted explicitly; declared here, inside the
  # service module (same pattern as ../garage, ../openBao, ../vaultWarden,
  # ../kubernetes). the parent directory is persisted (not just
  # services.postgresql.dataDir) so the cluster survives PG major upgrades
  environment.persistence."/persist".directories = [
    "/var/lib/postgresql"
  ];

  # the agent hosts need to reach the postgresql port over the LAN
  networking.firewall.allowedTCPPorts = [ 5432 ];

  # advertise the postgresql server over mDNS (see ../avahi.nix) so the agent
  # hosts can discover it as wranHearst.local instead of hardcoding addresses
  services.avahi.extraServiceFiles.postgresql = ''
    <?xml version="1.0" standalone='no'?><!--*-nxml-*-->
    <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
    <service-group>
      <name replace-wildcards="yes">postgresql on %h</name>
      <service>
        <type>_postgresql._tcp</type>
        <port>5432</port>
      </service>
    </service-group>
  '';
}
