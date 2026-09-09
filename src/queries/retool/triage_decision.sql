-- ============================================================
-- triage_decision — the audit trail behind the Triage Workbench
--
-- decision_id       surrogate key; the natural key would be note_id, but
--                   see the index note below
-- decided_by        populated from Retool's authenticated session
--                   (current_user.email), never from operator input, so the
--                   trail cannot be spoofed by the person being audited
-- decided_at_utc    defaults to now(); UTC to match every other timestamp
--                   in the replica
--
-- idx_triage_decision_one_per_note is what makes bulk commit safe to
-- double-submit: ON CONFLICT (note_id) DO NOTHING has nothing to conflict
-- against without it. The original UNIQUE (note_id, decided_at_utc) could
-- never fire, since decided_at_utc differs on every insert.
--
-- KNOWN ISSUE: this index also blocks corrections, which contradicts
-- Compliance's reversibility requirement (R-04). See DECISIONS.md Conflict 4
-- for the partial-index fix.
-- ============================================================

CREATE TABLE triage_decision (
    decision_id       bigserial   PRIMARY KEY,
    note_id           text        NOT NULL,
    disposition       text        NOT NULL,
    reason_code       text        NOT NULL,
    decided_by        text,
    decided_at_utc    timestamp   NOT NULL DEFAULT now(),
    UNIQUE (note_id, decided_at_utc)
);

CREATE UNIQUE INDEX idx_triage_decision_one_per_note
    ON triage_decision (note_id);