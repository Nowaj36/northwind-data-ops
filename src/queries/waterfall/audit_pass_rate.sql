-- ============================================================
-- WATERFALL ROW 0 — baseline, reproduces the reported figures
-- Result: audited_notes = 1705, pass_rate_pct = 79.9
-- ============================================================
SELECT COUNT(*) AS audited_notes,
    ROUND(100.0 * SUM(CASE WHEN a.pass_fail = 'PASS' THEN 1 ELSE 0 END)
          / COUNT(*), 1) AS pass_rate_pct
FROM note n
JOIN note_audit a ON a.note_id = n.note_id
JOIN clinician c ON c.clinician_id = n.clinician_id
WHERE n.submitted_at_utc 
    BETWEEN TIMESTAMP '2026-04-01' AND TIMESTAMP '2026-06-30';



-- ============================================================
-- WATERFALL ROW 1 — exclude void notes
-- Result: audited_notes = 1687, pass_rate_pct = 79.9  (Δ -18, Δ 0.0)
-- ============================================================
SELECT COUNT(*) AS audited_notes,
    ROUND(100.0 * SUM(CASE WHEN a.pass_fail = 'PASS' THEN 1 ELSE 0 END)
          / COUNT(*), 1) AS pass_rate_pct
FROM note n
JOIN note_audit a ON a.note_id = n.note_id
JOIN clinician c ON c.clinician_id = n.clinician_id
WHERE n.submitted_at_utc 
    BETWEEN TIMESTAMP '2026-04-01' AND TIMESTAMP '2026-06-30'
AND n.is_void = false;  -- ← fix 1 added



-- ============================================================
-- WATERFALL ROW 2 — clinician SCD fan-out fix
-- Result: audited_notes = 1562, pass_rate_pct = 79.8  (Δ -125, Δ -0.1)
-- Validation: 4 clinicians (CL-1004/1018/1029/1045) had 2 rows each;
--   250 fan-out rows / 2 = 125 unique notes. 60 clinicians, each with
--   exactly 1 current record. No orphans. Fix removes duplication only.
-- ============================================================
SELECT COUNT(*) AS audited_notes,
    ROUND(100.0 * SUM(CASE WHEN a.pass_fail = 'PASS' THEN 1 ELSE 0 END)
          / COUNT(*), 1) AS pass_rate_pct
FROM note n
JOIN note_audit a ON a.note_id = n.note_id
JOIN clinician c ON c.clinician_id = n.clinician_id
     AND c.is_current_record = true      -- ← fix 2 added
WHERE n.submitted_at_utc 
    BETWEEN TIMESTAMP '2026-04-01' AND TIMESTAMP '2026-06-30'
  AND n.is_void = false;



-- WATERFALL ROW 3 — deduplicate notes, keep latest ingestion per note_id
WITH deduped_note AS (
  SELECT DISTINCT ON (note_id) *
  FROM note
  ORDER BY note_id, ingested_at_utc DESC
)
SELECT COUNT(*) AS audited_notes,
    ROUND(100.0 * SUM(CASE WHEN a.pass_fail = 'PASS' THEN 1 ELSE 0 END)
          / COUNT(*), 1) AS pass_rate_pct
FROM deduped_note n
JOIN note_audit a ON a.note_id = n.note_id
JOIN clinician c ON c.clinician_id = n.clinician_id
     AND c.is_current_record = true
WHERE n.submitted_at_utc BETWEEN TIMESTAMP '2026-04-01' AND TIMESTAMP '2026-06-30'
  AND n.is_void = false;



-- WATERFALL ROW 4 — recompute pass/fail against the effective rubric threshold
WITH deduped_note AS (
  SELECT DISTINCT ON (note_id) *
  FROM note ORDER BY note_id, ingested_at_utc DESC
),
thresholds AS (
  SELECT DISTINCT rubric_version, pass_threshold FROM rubric_weight
)
SELECT COUNT(*) AS audited_notes,
    ROUND(100.0 * SUM(CASE WHEN a.composite_score >= t.pass_threshold THEN 1 ELSE 0 END)
          / COUNT(*), 1) AS pass_rate_pct
FROM deduped_note n
JOIN note_audit a ON a.note_id = n.note_id
JOIN thresholds t ON t.rubric_version = a.rubric_version
JOIN clinician c ON c.clinician_id = n.clinician_id
     AND c.is_current_record = true
WHERE n.submitted_at_utc BETWEEN TIMESTAMP '2026-04-01' AND TIMESTAMP '2026-06-30'
  AND n.is_void = false;



-- WATERFALL ROW 5 — quarter defined on the America/Chicago business day
WITH deduped_note AS (
  SELECT DISTINCT ON (note_id) *
  FROM note ORDER BY note_id, ingested_at_utc DESC
),
thresholds AS (
  SELECT DISTINCT rubric_version, pass_threshold FROM rubric_weight
)
SELECT COUNT(*) AS audited_notes,
    ROUND(100.0 * SUM(CASE WHEN a.composite_score >= t.pass_threshold THEN 1 ELSE 0 END)
          / COUNT(*), 1) AS pass_rate_pct,
    ROUND(AVG(a.composite_score)::numeric, 4) AS avg_composite
FROM deduped_note n
JOIN note_audit a ON a.note_id = n.note_id
JOIN thresholds t ON t.rubric_version = a.rubric_version
JOIN clinician c ON c.clinician_id = n.clinician_id
     AND c.is_current_record = true
WHERE (n.submitted_at_utc AT TIME ZONE 'UTC' AT TIME ZONE 'America/Chicago')::date
        BETWEEN DATE '2026-04-01' AND DATE '2026-06-30'
  AND n.is_void = false;



-- WATERFALL ROW 6 (FINAL) — recompute composite from rubric weights,
-- then evaluate against the effective threshold, on the Chicago business day
WITH deduped_note AS (
  SELECT DISTINCT ON (note_id) * FROM note ORDER BY note_id, ingested_at_utc DESC
),
w AS (
  SELECT rubric_version,
         MAX(CASE WHEN dimension='accuracy'     THEN weight END) AS w_acc,
         MAX(CASE WHEN dimension='completeness' THEN weight END) AS w_comp,
         MAX(CASE WHEN dimension='formatting'   THEN weight END) AS w_fmt,
         MAX(CASE WHEN dimension='terminology'  THEN weight END) AS w_term,
         MAX(CASE WHEN dimension='hpi'          THEN weight END) AS w_hpi,
         MAX(CASE WHEN dimension='ros'          THEN weight END) AS w_ros,
         MAX(CASE WHEN dimension='plan'         THEN weight END) AS w_plan,
         MAX(pass_threshold)                                     AS pass_threshold
  FROM rubric_weight GROUP BY rubric_version
)
SELECT
  COUNT(*) AS audited_notes,
  ROUND(100.0 * SUM(CASE WHEN
      (a.score_accuracy*w.w_acc + a.score_completeness*w.w_comp
     + a.score_formatting*w.w_fmt + a.score_terminology*w.w_term
     + a.score_hpi*w.w_hpi + a.score_ros*w.w_ros + a.score_plan*w.w_plan)
      >= w.pass_threshold THEN 1 ELSE 0 END) / COUNT(*), 1) AS pass_rate_pct,
  ROUND(AVG(a.score_accuracy*w.w_acc + a.score_completeness*w.w_comp
     + a.score_formatting*w.w_fmt + a.score_terminology*w.w_term
     + a.score_hpi*w.w_hpi + a.score_ros*w.w_ros + a.score_plan*w.w_plan)::numeric, 4)
     AS avg_composite
FROM deduped_note n
JOIN note_audit a ON a.note_id = n.note_id
JOIN w ON w.rubric_version = a.rubric_version
JOIN clinician c ON c.clinician_id = n.clinician_id AND c.is_current_record = true
WHERE (n.submitted_at_utc AT TIME ZONE 'UTC' AT TIME ZONE 'America/Chicago')::date
        BETWEEN DATE '2026-04-01' AND DATE '2026-06-30'
  AND n.is_void = false;