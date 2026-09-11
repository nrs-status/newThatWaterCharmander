-- pi-json-span-processor ingestion schema (idempotent)
--
-- Ingests the JSON-lines span stream produced by `pi-json-span-processor'
-- (see its SPEC.md) into the `pi' database:
--
--   * every span line (`"span": "agent" | "turn" | "message" |
--     "tool_execution"') is stored in `pi_stream_spans';
--   * every `session' passthrough line is stored in `pi_stream_sessions';
--   * anything else is silently skipped.
--
-- Ingestion is performed line by line through `pi_stream_ingest(jsonb)':
--
--   SELECT pi_stream_ingest($json${...span line...}$json$::jsonb);
--
-- or, for a whole processor run, from the shell (dollar-quoted lines):
--
--   pi-json-span-processor < events.jsonl \
--     | jq -r '"SELECT pi_stream_ingest($json$" + . + "$json$::jsonb);"' \
--     | psql -d pi -v ON_ERROR_STOP=1

CREATE TABLE IF NOT EXISTS pi_stream_spans (
    id              BIGSERIAL PRIMARY KEY,
    span            TEXT NOT NULL
                    CHECK (span IN ('agent', 'turn', 'message', 'tool_execution')),
    span_id         TEXT NOT NULL UNIQUE,   -- processor-generated id ("span-N")
    parent_id       TEXT,                   -- parentId (agent id for turns, turn id
                                            -- for messages / tool executions)
    start_time      TIMESTAMPTZ NOT NULL,
    end_time        TIMESTAMPTZ NOT NULL,
    duration_ms     DOUBLE PRECISION GENERATED ALWAYS AS
                        (EXTRACT(EPOCH FROM (end_time - start_time)) * 1000)
                        STORED,
    content         TEXT,                   -- message / tool_execution result text
    content_blocks  JSONB,                  -- message: structured blocks
                                            -- (text / thinking / toolCall)
    tool_name       TEXT,                   -- tool_execution
    is_error        BOOLEAN,                -- tool_execution
    usage           JSONB,                  -- message / tool_execution token+cost details
    raw             JSONB NOT NULL,         -- the verbatim ingested line
    ingested_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS pi_stream_spans_span_idx  ON pi_stream_spans (span);
CREATE INDEX IF NOT EXISTS pi_stream_spans_parent_idx ON pi_stream_spans (parent_id);
CREATE INDEX IF NOT EXISTS pi_stream_spans_start_idx ON pi_stream_spans (start_time);

-- Verbatim `session' passthrough lines (one JSON object per line).
CREATE TABLE IF NOT EXISTS pi_stream_sessions (
    id          BIGSERIAL PRIMARY KEY,
    session     JSONB NOT NULL,
    ingested_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Ingest one output line of pi-json-span-processor.
-- Returns the kind of line ingested: 'span', 'session' or 'skipped'.
CREATE OR REPLACE FUNCTION pi_stream_ingest(line JSONB)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    kind TEXT;
BEGIN
    IF line IS NULL OR jsonb_typeof(line) <> 'object' THEN
        RETURN 'skipped';
    END IF;

    kind := COALESCE(line->>'span', line->>'type');

    IF kind IN ('agent', 'turn', 'message', 'tool_execution') THEN
        INSERT INTO pi_stream_spans (
            span, span_id, parent_id, start_time, end_time,
            content, content_blocks, tool_name, is_error, usage, raw
        ) VALUES (
            kind,
            line->>'id',
            NULLIF(line->>'parentId', ''),
            (line->>'start')::timestamptz,
            (line->>'end')::timestamptz,
            CASE WHEN kind IN ('message', 'tool_execution')
                 THEN NULLIF(line->>'content', '') END,
            CASE WHEN kind = 'message' THEN line->'contentBlocks' END,
            CASE WHEN kind = 'tool_execution' THEN line->>'toolName' END,
            CASE WHEN kind = 'tool_execution'
                 THEN COALESCE((line->>'isError')::boolean, false) END,
            CASE WHEN kind IN ('message', 'tool_execution')
                 THEN COALESCE(line->'usage', '{}'::jsonb) END,
            line
        )
        ON CONFLICT (span_id) DO NOTHING;   -- idempotent re-ingestion
        RETURN 'span';

    ELSIF kind = 'session' THEN
        INSERT INTO pi_stream_sessions (session) VALUES (line);
        RETURN 'session';

    ELSE
        RETURN 'skipped';
    END IF;
END;
$$;
