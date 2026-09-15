-- arunman ingestion schema (idempotent)
--
-- `arunman' (from the frontArmToPlane flake, see its
-- templeArtemisEphesus/arunman/SPEC.md) tracks pi microvm runs in the `run'
-- table of the `arunman' database: the `run' subcommand inserts one entry
-- per job (status initializing -> ongoing -> done/terminated, with output
-- and endTime filled in on completion) and the `list' subcommand queries
-- them.
--
-- The table definition mirrors the one arunman itself creates on first use
-- with `CREATE TABLE IF NOT EXISTS', so pre-provisioning it here means the
-- tool (which may connect as a non-owner role over the network) never needs
-- CREATE privileges on the database.

CREATE TABLE IF NOT EXISTS run (
    id          SERIAL PRIMARY KEY,
    config      TEXT NOT NULL,          -- nix store path of the run flake
    workdir     TEXT NOT NULL,          -- mktemp -d workdir of the run
    status      TEXT NOT NULL
                CHECK (status = ANY (ARRAY['ongoing'::text, 'done'::text,
                                           'initializing'::text,
                                           'terminated'::text])),
    "startTime" TIMESTAMPTZ NOT NULL,
    "endTime"   TIMESTAMPTZ,
    output      TEXT                    -- nix store path of `nix store add workdir'
);

CREATE INDEX IF NOT EXISTS run_status_idx     ON run (status);
CREATE INDEX IF NOT EXISTS run_start_time_idx ON run ("startTime");
