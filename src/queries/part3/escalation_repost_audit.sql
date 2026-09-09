CREATE TABLE escalation_repost_audit (
    escalation_id     text        NOT NULL,
    attempt_no        integer     NOT NULL,
    posted_at_utc     timestamp   NOT NULL DEFAULT now(),
    http_status       integer,
    response_body     text,
    outcome           text        NOT NULL,
    run_id            text        NOT NULL,
    PRIMARY KEY (escalation_id, attempt_no)
);

CREATE UNIQUE INDEX idx_repost_success_once
    ON escalation_repost_audit (escalation_id)
    WHERE outcome = 'SUCCESS';

CREATE INDEX idx_repost_run ON escalation_repost_audit (run_id);