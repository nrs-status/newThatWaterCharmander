{ pkgs, ... }:
let
  nodesSchema = pkgs.writeText "nodes-schema.sql" ''
    CREATE TABLE IF NOT EXISTS nodes (
        id INTEGER PRIMARY KEY,
        topic TEXT,
        title TEXT,
        body TEXT,
        tags TEXT,             -- comma-sep
        fuzzyAux TEXT,
        creationDate TEXT      -- ISO 8601
    );
  '';
  psql = "${pkgs.postgresql}/bin/psql";
in
{
  services.postgresql = {
    enable = true;

    ensureDatabases = [ "nodes" ];

    ensureUsers = [
      { name = "sieyes"; }
    ];
  };

  # Grants the "nodes" database to sieyes and idempotently creates the
  # "nodes" table, transferring its ownership to sieyes so that the user
  # sieyes has full read/write access to both the database and the table.
  systemd.services.postgresql-nodes-schema = {
    description = "Ensure the 'nodes' table exists in the PostgreSQL 'nodes' database owned by sieyes";
    after = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      User = "postgres";
      RemainAfterExit = true;
    };

    script = ''
      ${psql} -d nodes -c 'ALTER DATABASE "nodes" OWNER TO "sieyes"'
      ${psql} -d nodes -f ${nodesSchema}
      ${psql} -d nodes -c 'ALTER TABLE nodes OWNER TO "sieyes"'
    '';
  };
}
