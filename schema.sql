-- =====================================================================
--  Ambient Ops operational replica — DDL as it exists today.
--  Shipped deliberately as-is: no primary keys, no foreign keys,
--  no indexes. It is a change-feed landing area, not a modelled
--  warehouse. If you have views on that, we want to hear them.
--
--  Load order does not matter. To import:
--    Retool DB : Resources -> Retool Database -> Import CSV (per table)
--    Postgres  : run this file, then, from the /data directory:
--                \copy note        FROM 'note.csv'        CSV HEADER
--                \copy note_audit  FROM 'note_audit.csv'  CSV HEADER
--                \copy clinician   FROM 'clinician.csv'   CSV HEADER
--                \copy mds         FROM 'mds.csv'         CSV HEADER
--                \copy sla_config  FROM 'sla_config.csv'  CSV HEADER
--                \copy rubric_weight FROM 'rubric_weight.csv' CSV HEADER
--                \copy escalation  FROM 'escalation.csv'  CSV HEADER
-- =====================================================================

CREATE TABLE note (
    note_id           text,
    ingestion_id      text,
    encounter_id      text,
    clinician_id      text,
    mds_id            text,
    product_line      text,
    priority          text,
    template_id       text,
    source_channel    text,
    word_count        integer,        -- nullable; NULL <> 0
    submitted_at_utc  timestamp,      -- UTC instant
    delivered_at_utc  timestamp,      -- UTC instant
    ingested_at_utc   timestamp,      -- UTC instant
    is_void           boolean,
    void_reason       text
);

CREATE TABLE clinician (
    clinician_id          text,
    clinician_name        text,
    specialty             text,
    region                text,
    home_timezone         text,
    employment_status     text,
    record_effective_from date,
    record_effective_to   date,
    is_current_record     boolean
);

CREATE TABLE mds (
    mds_id     text,
    mds_name   text,
    pod        text,
    tier       text,
    hire_date  date,
    status     text
);

CREATE TABLE note_audit (
    audit_id           text,
    note_id            text,
    auditor_mds_id     text,
    audited_at_utc     timestamp,
    rubric_version     text,
    score_accuracy     numeric,
    score_completeness numeric,
    score_formatting   numeric,
    score_terminology  numeric,
    score_hpi          numeric,
    score_ros          numeric,
    score_plan         numeric,
    composite_score    numeric,   -- DERIVED by ETL from the sub-scores
    pass_fail          text       -- DERIVED by ETL from composite_score
);

CREATE TABLE rubric_weight (
    rubric_version text,
    dimension      text,
    weight         numeric,
    effective_from date,
    pass_threshold numeric
);

CREATE TABLE sla_config (
    config_id      text,
    product_line   text,
    priority       text,
    target_minutes integer,
    effective_from date,
    effective_to   date
);

CREATE TABLE escalation (
    escalation_id         text,
    note_id               text,
    created_at_utc        timestamp,
    slack_channel         text,
    slack_thread_ts       text,      -- populated only after a successful post
    status                text,      -- OPEN | RESOLVED | PENDING_POST
    assignee_mds_id       text,
    first_response_at_utc timestamp,
    resolved_at_utc       timestamp,
    attempt_count         integer,
    last_api_error        text
);

-- Your own tables (audit trail for Part 3, any modelled views) belong in
-- a schema or prefix of your choosing. Ship the DDL in your repo.
