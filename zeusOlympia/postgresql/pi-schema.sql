-- pi-agent-cli telemetry schema (idempotent)

-- One row per completed telemetry span, following pi's vendor-neutral
-- telemetry contracts (@earendil-works/pi-telemetry TelemetryContext).
CREATE TABLE IF NOT EXISTS pi_spans (
    id              BIGSERIAL PRIMARY KEY,
    trace_id        TEXT NOT NULL,
    span_id         TEXT NOT NULL UNIQUE,
    parent_span_id  TEXT,
    name            TEXT NOT NULL,
    start_time      TIMESTAMPTZ NOT NULL,
    end_time        TIMESTAMPTZ,
    duration_ms     DOUBLE PRECISION,
    status          TEXT NOT NULL DEFAULT 'ok',
    status_name     TEXT,
    status_message  TEXT,
    attributes      JSONB NOT NULL DEFAULT '{}'::jsonb,
    resource        JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS pi_spans_trace_idx ON pi_spans (trace_id);
CREATE INDEX IF NOT EXISTS pi_spans_name_idx ON pi_spans (name);
CREATE INDEX IF NOT EXISTS pi_spans_parent_idx ON pi_spans (parent_span_id);

-- Timed events recorded inside spans.
CREATE TABLE IF NOT EXISTS pi_span_events (
    id          BIGSERIAL PRIMARY KEY,
    span_id     TEXT NOT NULL REFERENCES pi_spans (span_id) ON DELETE CASCADE,
    name        TEXT NOT NULL,
    time        TIMESTAMPTZ NOT NULL,
    attributes  JSONB NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX IF NOT EXISTS pi_span_events_span_idx ON pi_span_events (span_id);

-- One row per agent run (a prompt fed to the pi agent).
CREATE TABLE IF NOT EXISTS pi_runs (
    id                  BIGSERIAL PRIMARY KEY,
    trace_id            TEXT NOT NULL,
    session_id          TEXT NOT NULL,
    run_span_id         TEXT,
    prompt              TEXT NOT NULL,
    answer              TEXT,
    provider            TEXT,
    model               TEXT,
    thinking_level      TEXT,
    started_at          TIMESTAMPTZ NOT NULL,
    ended_at            TIMESTAMPTZ NOT NULL,
    duration_ms         DOUBLE PRECISION NOT NULL,
    outcome             TEXT NOT NULL,
    error_message       TEXT,
    input_tokens        BIGINT NOT NULL DEFAULT 0,
    output_tokens       BIGINT NOT NULL DEFAULT 0,
    cache_read_tokens   BIGINT NOT NULL DEFAULT 0,
    cache_write_tokens  BIGINT NOT NULL DEFAULT 0,
    reasoning_tokens    BIGINT,
    cost_total          DOUBLE PRECISION NOT NULL DEFAULT 0,
    tool_call_count     INTEGER NOT NULL DEFAULT 0,
    turn_count          INTEGER NOT NULL DEFAULT 0,
    span_count          INTEGER NOT NULL DEFAULT 0,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS pi_runs_trace_idx ON pi_runs (trace_id);
