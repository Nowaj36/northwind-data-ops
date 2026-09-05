-- Q2 baseline as-is — reported "12.8% breach, median 18.5 min"
SELECT
    COUNT(*) AS notes_measured,
    ROUND(100.0 * SUM(CASE WHEN EXTRACT(EPOCH FROM (n.delivered_at_utc - n.submitted_at_utc))/60.0
                                > s.target_minutes THEN 1 ELSE 0 END) / COUNT(*), 1) AS breach_rate_pct,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (
        ORDER BY EXTRACT(EPOCH FROM (n.delivered_at_utc - n.submitted_at_utc))/60.0
    )::numeric, 1) AS median_minutes
FROM note n
JOIN sla_config s ON s.product_line = n.product_line AND s.priority = n.priority
LEFT JOIN escalation e ON e.note_id = n.note_id
WHERE n.submitted_at_utc BETWEEN TIMESTAMP '2026-04-01' AND TIMESTAMP '2026-06-30'
  AND e.status <> 'RESOLVED';



-- What population did the reported 12.8% actually cover?
SELECT
  (SELECT COUNT(*) FROM note
    WHERE submitted_at_utc BETWEEN TIMESTAMP '2026-04-01' AND TIMESTAMP '2026-06-30')
      AS all_notes_in_utc_window,
  (SELECT COUNT(DISTINCT n.note_id)
     FROM note n
     JOIN escalation e ON e.note_id = n.note_id
    WHERE n.submitted_at_utc BETWEEN TIMESTAMP '2026-04-01' AND TIMESTAMP '2026-06-30'
      AND e.status <> 'RESOLVED')
      AS notes_with_non_resolved_escalation,
  (SELECT COUNT(*)
     FROM note n
     JOIN sla_config s ON s.product_line = n.product_line AND s.priority = n.priority
     LEFT JOIN escalation e ON e.note_id = n.note_id
    WHERE n.submitted_at_utc BETWEEN TIMESTAMP '2026-04-01' AND TIMESTAMP '2026-06-30'
      AND e.status <> 'RESOLVED')
      AS rows_after_sla_fanout;




-- METRIC 2 — TRUE VALUE
-- Corrections: drop the escalation join entirely (it is not part of the
-- metric's definition), deduplicate notes, exclude voids, effective-date the
-- SLA lookup against the note's own Chicago business date, define the quarter
-- on the Chicago business day.
WITH deduped_note AS (
  SELECT DISTINCT ON (note_id) * FROM note ORDER BY note_id, ingested_at_utc DESC
),
scoped AS (
  SELECT n.*,
         (n.submitted_at_utc AT TIME ZONE 'UTC' AT TIME ZONE 'America/Chicago')::date AS submit_day_chicago
  FROM deduped_note n
  WHERE n.is_void = false
),
with_target AS (
  SELECT sc.note_id,
         EXTRACT(EPOCH FROM (sc.delivered_at_utc - sc.submitted_at_utc))/60.0 AS delivery_minutes,
         s.target_minutes
  FROM scoped sc
  JOIN sla_config s
    ON s.product_line = sc.product_line
   AND s.priority     = sc.priority
   AND sc.submit_day_chicago >= s.effective_from
   AND (s.effective_to IS NULL OR sc.submit_day_chicago <= s.effective_to)
  WHERE sc.submit_day_chicago BETWEEN DATE '2026-04-01' AND DATE '2026-06-30'
)
SELECT
  COUNT(*) AS notes_measured,
  ROUND(100.0 * SUM(CASE WHEN delivery_minutes > target_minutes THEN 1 ELSE 0 END)
        / COUNT(*), 1) AS breach_rate_pct,
  ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY delivery_minutes)::numeric, 1) AS median_minutes
FROM with_target;