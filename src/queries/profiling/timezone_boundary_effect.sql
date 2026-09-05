-- ============================================================
-- Timezone boundary effect on the audited-note population
-- Supports: ADR 001, RECONCILIATION.md D5 / waterfall row 5
-- Run date: 2026-09-05
-- Result: entered = 21, left_window = 1, unchanged = 1545
--         -> net +20 audited notes vs the UTC window
-- ============================================================
WITH deduped_note AS (
  SELECT DISTINCT ON (note_id) * FROM note ORDER BY note_id, ingested_at_utc DESC
),
scoped AS (
  SELECT n.note_id,
         (n.submitted_at_utc BETWEEN TIMESTAMP '2026-04-01' AND TIMESTAMP '2026-06-30') AS in_utc,
         ((n.submitted_at_utc AT TIME ZONE 'UTC' AT TIME ZONE 'America/Chicago')::date
            BETWEEN DATE '2026-04-01' AND DATE '2026-06-30') AS in_chicago
  FROM deduped_note n
  JOIN note_audit a ON a.note_id = n.note_id
  JOIN clinician c ON c.clinician_id = n.clinician_id AND c.is_current_record = true
  WHERE n.is_void = false
)
SELECT
  SUM(CASE WHEN NOT in_utc AND in_chicago THEN 1 ELSE 0 END) AS entered,
  SUM(CASE WHEN in_utc AND NOT in_chicago THEN 1 ELSE 0 END) AS left_window,
  SUM(CASE WHEN in_utc AND in_chicago THEN 1 ELSE 0 END)     AS unchanged
FROM scoped;