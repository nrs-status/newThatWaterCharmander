{ pkgs, ... }:
let
  docSchema = pkgs.writeText "doc-schema.sql" (builtins.readFile ./doc-schema.sql);
<<<<<<< HEAD
||||||| parent of e3c16fe (Squash commits from add-pi-streamer-sql-proper)
  piSchema = pkgs.writeText "pi-schema.sql" (builtins.readFile ./pi-schema.sql);
=======
  piSchema = pkgs.writeText "pi-schema.sql" (builtins.readFile ./pi-schema.sql);
  # schema + ingest function for the JSON-lines span stream produced by
  # pi-json-span-processor (see newFrontArmToPlane/pi-json-span-processor/SPEC.md)
  piStreamSchema =
    pkgs.writeText "pi-stream-schema.sql" (builtins.readFile ./pi-stream-schema.sql);
>>>>>>> e3c16fe (Squash commits from add-pi-streamer-sql-proper)
  psql = "${pkgs.postgresql}/bin/psql";
in
{
  services.postgresql = {
    enable = true;

    ensureDatabases = [
      "doc"
      "pi"
    ];

    ensureUsers = [
      { name = "sieyes"; }
    ];
  };

  systemd.services.mypsql = {
    after = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];
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
<<<<<<< HEAD
||||||| parent of e3c16fe (Squash commits from add-pi-streamer-sql-proper)
      
      ${psql} -d pi -c 'ALTER DATABASE "pi" OWNER TO "sieyes"'
      ${psql} -d pi -f ${piSchema}
      ${psql} -d pi -c 'ALTER TABLE pi_spans OWNER TO "sieyes"'
      ${psql} -d pi -c 'ALTER TABLE pi_span_events OWNER TO "sieyes"'
      ${psql} -d pi -c 'ALTER TABLE pi_runs OWNER TO "sieyes"'

=======
      
      ${psql} -d pi -c 'ALTER DATABASE "pi" OWNER TO "sieyes"'
      ${psql} -d pi -f ${piSchema}
      ${psql} -d pi -c 'ALTER TABLE pi_spans OWNER TO "sieyes"'
      ${psql} -d pi -c 'ALTER TABLE pi_span_events OWNER TO "sieyes"'
      ${psql} -d pi -c 'ALTER TABLE pi_runs OWNER TO "sieyes"'

      # pi-json-span-processor ingestion schema (idempotent)
      ${psql} -d pi -f ${piStreamSchema}
      ${psql} -d pi -c 'ALTER TABLE pi_stream_spans OWNER TO "sieyes"'
      ${psql} -d pi -c 'ALTER TABLE pi_stream_sessions OWNER TO "sieyes"'
      ${psql} -d pi -c 'ALTER FUNCTION pi_stream_ingest(jsonb) OWNER TO "sieyes"'

>>>>>>> e3c16fe (Squash commits from add-pi-streamer-sql-proper)
    '';
  };
}
