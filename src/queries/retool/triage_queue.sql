-- Triage queue: failed audits, built on the corrected Part 1 logic (R10)
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
  n.note_id,
  n.product_line,
  n.priority,
  n.submitted_at_utc,
  n.delivered_at_utc,
  m.mds_id,
  m.mds_name,
  c.clinician_id,
  c.clinician_name,
  a.audit_id,
  a.rubric_version,
  a.score_accuracy,
  a.score_completeness,
  a.score_formatting,
  a.score_terminology,
  a.score_hpi,
  a.score_ros,
  a.score_plan,
  ROUND((a.score_accuracy*w.w_acc + a.score_completeness*w.w_comp
       + a.score_formatting*w.w_fmt + a.score_terminology*w.w_term
       + a.score_hpi*w.w_hpi + a.score_ros*w.w_ros
       + a.score_plan*w.w_plan)::numeric, 4)                     AS composite_score,
  w.pass_threshold,
  ROUND(EXTRACT(EPOCH FROM (n.delivered_at_utc - n.submitted_at_utc))/60.0::numeric, 1)
                                                                   AS delivery_minutes,
  s.target_minutes                                                AS sla_target_minutes
FROM deduped_note n
JOIN mds m         ON m.mds_id = n.mds_id
JOIN clinician c   ON c.clinician_id = n.clinician_id AND c.is_current_record = true
JOIN note_audit a  ON a.note_id = n.note_id
JOIN w             ON w.rubric_version = a.rubric_version
JOIN sla_config s
     ON s.product_line = n.product_line
    AND s.priority     = n.priority
    AND (n.submitted_at_utc AT TIME ZONE 'UTC' AT TIME ZONE 'America/Chicago')::date
          >= s.effective_from
    AND ((n.submitted_at_utc AT TIME ZONE 'UTC' AT TIME ZONE 'America/Chicago')::date
          <= s.effective_to OR s.effective_to IS NULL)
WHERE n.is_void = false
  AND (a.score_accuracy*w.w_acc + a.score_completeness*w.w_comp
     + a.score_formatting*w.w_fmt + a.score_terminology*w.w_term
     + a.score_hpi*w.w_hpi + a.score_ros*w.w_ros + a.score_plan*w.w_plan) < w.pass_threshold
ORDER BY n.submitted_at_utc DESC;