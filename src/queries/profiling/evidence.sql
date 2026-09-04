-- Dedup rule validation: is the ingestion_id suffix always aligned
-- with ingested_at_utc ordering? (i.e. is "latest ingestion" unambiguous?)
SELECT
  COUNT(*) AS duplicate_note_ids,
  SUM(CASE WHEN latest_by_time = latest_by_suffix THEN 1 ELSE 0 END) AS rules_agree,
  SUM(CASE WHEN latest_by_time <> latest_by_suffix THEN 1 ELSE 0 END) AS rules_disagree
FROM (
  SELECT
    note_id,
    (ARRAY_AGG(ingestion_id ORDER BY ingested_at_utc DESC))[1] AS latest_by_time,
    (ARRAY_AGG(ingestion_id ORDER BY
       SPLIT_PART(ingestion_id, '-', 3)::int DESC))[1]         AS latest_by_suffix
  FROM note
  GROUP BY note_id
  HAVING COUNT(*) > 1
) x;


-- Does the stored pass_fail agree with the effective-dated rubric threshold?
SELECT
  a.rubric_version,
  r.pass_threshold,
  COUNT(*)                                                          AS audits,
  SUM(CASE WHEN a.pass_fail = 'PASS' THEN 1 ELSE 0 END)             AS stored_pass,
  SUM(CASE WHEN a.composite_score >= r.pass_threshold THEN 1 ELSE 0 END) AS recomputed_pass,
  SUM(CASE WHEN a.pass_fail = 'PASS'
            AND a.composite_score <  r.pass_threshold THEN 1 ELSE 0 END) AS false_pass,
  SUM(CASE WHEN a.pass_fail = 'FAIL'
            AND a.composite_score >= r.pass_threshold THEN 1 ELSE 0 END) AS false_fail
FROM note_audit a
JOIN (SELECT DISTINCT rubric_version, pass_threshold FROM rubric_weight) r
  ON r.rubric_version = a.rubric_version
GROUP BY a.rubric_version, r.pass_threshold
ORDER BY a.rubric_version;


-- How many non-void notes fall on 2026-06-30 (excluded by the BETWEEN bound)?
SELECT COUNT(*) AS notes_on_jun30
FROM note
WHERE submitted_at_utc > TIMESTAMP '2026-06-30'
  AND submitted_at_utc <  TIMESTAMP '2026-07-01'
  AND is_void = false;


-- Is the stored composite_score consistent with the rubric weights for its version?
WITH w AS (
  SELECT rubric_version,
         MAX(CASE WHEN dimension='accuracy'     THEN weight END) AS w_acc,
         MAX(CASE WHEN dimension='completeness' THEN weight END) AS w_comp,
         MAX(CASE WHEN dimension='formatting'   THEN weight END) AS w_fmt,
         MAX(CASE WHEN dimension='terminology'  THEN weight END) AS w_term,
         MAX(CASE WHEN dimension='hpi'          THEN weight END) AS w_hpi,
         MAX(CASE WHEN dimension='ros'          THEN weight END) AS w_ros,
         MAX(CASE WHEN dimension='plan'         THEN weight END) AS w_plan
  FROM rubric_weight GROUP BY rubric_version
),
recomputed AS (
  SELECT a.audit_id, a.rubric_version, a.composite_score,
         ROUND((a.score_accuracy*w.w_acc + a.score_completeness*w.w_comp
              + a.score_formatting*w.w_fmt + a.score_terminology*w.w_term
              + a.score_hpi*w.w_hpi + a.score_ros*w.w_ros
              + a.score_plan*w.w_plan)::numeric, 4) AS recomputed_composite
  FROM note_audit a
  JOIN w ON w.rubric_version = a.rubric_version
)
SELECT rubric_version,
       COUNT(*) AS audits,
       SUM(CASE WHEN ABS(composite_score - recomputed_composite) < 0.0001 THEN 1 ELSE 0 END) AS matches,
       SUM(CASE WHEN ABS(composite_score - recomputed_composite) >= 0.0001 THEN 1 ELSE 0 END) AS mismatches,
       ROUND(AVG(composite_score - recomputed_composite)::numeric, 4) AS avg_diff
FROM recomputed
GROUP BY rubric_version
ORDER BY rubric_version;