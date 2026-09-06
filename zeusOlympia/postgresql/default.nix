{ pkgs, ... }:
let
  docSchema = pkgs.writeText "doc-schema.sql" (builtins.readFile ./doc-schema.sql);
  piSchema = pkgs.writeText "pi-schema.sql" (builtins.readFile ./pi-schema.sql);
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

    script = ''
      ${psql} -d doc -c 'ALTER DATABASE "doc" OWNER TO "sieyes"'
      ${psql} -d doc -f ${docSchema}
      ${psql} -d doc -c 'ALTER TABLE nodes OWNER TO "sieyes"'
      
      ${psql} -d pi -c 'ALTER DATABASE "pi" OWNER TO "sieyes"'
      ${psql} -d pi -f ${piSchema}
      ${psql} -d pi -c 'ALTER TABLE pi_spans OWNER TO "sieyes"'
      ${psql} -d pi -c 'ALTER TABLE pi_span_events OWNER TO "sieyes"'
      ${psql} -d pi -c 'ALTER TABLE pi_runs OWNER TO "sieyes"'

    '';
  };
}
