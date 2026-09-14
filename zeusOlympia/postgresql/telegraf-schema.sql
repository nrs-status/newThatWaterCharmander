-- telemetry ingestion schema for the telegraf agents augtibcalcla and
-- lanchamarcou (see ../telegraf). One table per streaming host, matching the
-- schema telegraf's outputs.postgresql plugin creates when running with
-- tags_as_jsonb / fields_as_jsonb and
-- timestamp_column_type = "timestamp with time zone":
--
--   "time"   timestamptz
--   "tags"   jsonb (includes a "measurement" tag set by the starlark processor)
--   "fields" jsonb
--
-- applied idempotently by the mypsql systemd unit (./default.nix); the
-- telegraf role is created there (it is cluster-wide, not per-database).

CREATE TABLE IF NOT EXISTS telemetry_augtibcalcla (
    "time"   timestamptz NOT NULL,
    "tags"   jsonb NOT NULL DEFAULT '{}'::jsonb,
    "fields" jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS telemetry_lanchamarcou (
    "time"   timestamptz NOT NULL,
    "tags"   jsonb NOT NULL DEFAULT '{}'::jsonb,
    "fields" jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS telemetry_augtibcalcla_time_idx
    ON telemetry_augtibcalcla ("time");
CREATE INDEX IF NOT EXISTS telemetry_lanchamarcou_time_idx
    ON telemetry_lanchamarcou ("time");

-- the telegraf role only ever inserts; it must not be able to touch the
-- doc / pi databases or any other table
GRANT CONNECT ON DATABASE telemetry TO telegraf;
GRANT USAGE ON SCHEMA public TO telegraf;
GRANT INSERT ON telemetry_augtibcalcla, telemetry_lanchamarcou TO telegraf;
