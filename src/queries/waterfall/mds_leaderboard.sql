-- Q4 CORRECTED — MDS leaderboard
-- Fixes: group by mds_id (not name), exclude non-ACTIVE staff, deduplicate
-- notes, exclude voids, recompute composite from the effective rubric weights,
-- audited notes only, Chicago business day, NULL word_count left as NULL.
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
),
scored AS (
  SELECT m.mds_id, m.mds_name, m.tier,
         n.note_id, n.word_count,
         (a.score_accuracy*w.w_acc + a.score_completeness*w.w_comp
        + a.score_formatting*w.w_fmt + a.score_terminology*w.w_term
        + a.score_hpi*w.w_hpi + a.score_ros*w.w_ros + a.score_plan*w.w_plan) AS composite,
         w.pass_threshold
  FROM deduped_note n
  JOIN mds m        ON m.mds_id = n.mds_id AND m.status = 'ACTIVE'
  JOIN note_audit a ON a.note_id = n.note_id
  JOIN w            ON w.rubric_version = a.rubric_version
  WHERE n.is_void = false
    AND (n.submitted_at_utc AT TIME ZONE 'UTC' AT TIME ZONE 'America/Chicago')::date
          BETWEEN DATE '2026-04-01' AND DATE '2026-06-30'
)
SELECT
  mds_id,
  mds_name,
  tier,
  COUNT(*)                                          AS notes_audited,
  ROUND(AVG(composite)::numeric, 4)                 AS avg_composite,
  ROUND(100.0 * SUM(CASE WHEN composite >= pass_threshold THEN 1 ELSE 0 END)
        / COUNT(*), 1)                              AS pass_rate_pct,
  ROUND(AVG(word_count)::numeric, 1)                AS avg_word_count,
  SUM(CASE WHEN word_count < 50 THEN 1 ELSE 0 END)  AS short_note_flags,
  SUM(CASE WHEN word_count IS NULL THEN 1 ELSE 0 END) AS unknown_word_count
FROM scored
GROUP BY mds_id, mds_name, tier
ORDER BY avg_composite DESC;



-- Decision B evidence — "Domingo, Rafael" is two people, and the merge
-- conceals a genuine bottom-five performer.
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
         MAX(CASE WHEN dimension='plan'         THEN weight END) AS w_plan
  FROM rubric_weight GROUP BY rubric_version
)
SELECT
  m.mds_id, m.mds_name, m.status, m.tier, m.hire_date,
  COUNT(*)                          AS notes_audited,
  ROUND(AVG(a.score_accuracy*w.w_acc + a.score_completeness*w.w_comp
          + a.score_formatting*w.w_fmt + a.score_terminology*w.w_term
          + a.score_hpi*w.w_hpi + a.score_ros*w.w_ros
          + a.score_plan*w.w_plan)::numeric, 4) AS avg_composite
FROM deduped_note n
JOIN mds m        ON m.mds_id = n.mds_id
JOIN note_audit a ON a.note_id = n.note_id
JOIN w            ON w.rubric_version = a.rubric_version
WHERE n.is_void = false
  AND (n.submitted_at_utc AT TIME ZONE 'UTC' AT TIME ZONE 'America/Chicago')::date
        BETWEEN DATE '2026-04-01' AND DATE '2026-06-30'
  AND m.mds_name IN ('Domingo, Rafael', 'Achebe, Noor', 'Petronella, Emeka')
GROUP BY m.mds_id, m.mds_name, m.status, m.tier, m.hire_date
ORDER BY m.mds_name, m.mds_id;