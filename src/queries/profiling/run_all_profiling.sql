-- =====================================================================
--  Northwind Data Ops — Table profiling (Part 1, section 3.1)
--  Purpose: characterise grain and key uniqueness of every table BEFORE
--           touching the provided queries.
--  Usage:
--    psql -d "<connection string>" -f run_all_profiling.sql -o profiling-results.txt
-- =====================================================================

\echo '=== P01: clinician SCD fan-out (is clinician_id unique?) ==='
SELECT COUNT(*)                     AS total_rows,
       COUNT(DISTINCT clinician_id) AS unique_clinicians,
       COUNT(*) - COUNT(DISTINCT clinician_id) AS extra_rows
FROM clinician;

\echo ''
\echo '=== P02: which clinicians have multiple rows ==='
SELECT clinician_id,
       COUNT(*)                                    AS row_count,
       SUM(CASE WHEN is_current_record THEN 1 ELSE 0 END) AS current_rows
FROM clinician
GROUP BY clinician_id
HAVING COUNT(*) > 1
ORDER BY row_count DESC, clinician_id;

\echo ''
\echo '=== P03: note_audit grain (one audit per note? duplicate audit_id?) ==='
SELECT COUNT(*)                   AS total_audits,
       COUNT(DISTINCT audit_id)   AS unique_audit_ids,
       COUNT(DISTINCT note_id)    AS unique_notes_audited,
       COUNT(*) - COUNT(DISTINCT note_id) AS repeat_audits
FROM note_audit;

\echo ''
\echo '=== P03b: notes audited more than once ==='
SELECT note_id, COUNT(*) AS audit_count
FROM note_audit
GROUP BY note_id
HAVING COUNT(*) > 1
ORDER BY audit_count DESC, note_id
LIMIT 20;

\echo ''
\echo '=== P04: note grain (duplicate note_id? re-ingestion?) ==='
SELECT COUNT(*)                       AS total_rows,
       COUNT(DISTINCT note_id)        AS unique_note_ids,
       COUNT(DISTINCT ingestion_id)   AS unique_ingestion_ids,
       COUNT(DISTINCT encounter_id)   AS unique_encounter_ids
FROM note;

\echo ''
\echo '=== P04b: note_ids appearing more than once ==='
SELECT note_id, COUNT(*) AS row_count
FROM note
GROUP BY note_id
HAVING COUNT(*) > 1
ORDER BY row_count DESC, note_id
LIMIT 20;

\echo ''
\echo '=== P05: void notes ==='
SELECT is_void, COUNT(*) AS notes
FROM note
GROUP BY is_void
ORDER BY is_void;

\echo ''
\echo '=== P05b: void reasons ==='
SELECT void_reason, COUNT(*) AS notes
FROM note
WHERE is_void IS TRUE
GROUP BY void_reason
ORDER BY notes DESC;

\echo ''
\echo '=== P06: escalation status distribution ==='
SELECT status,
       COUNT(*)                                              AS escalations,
       SUM(CASE WHEN slack_thread_ts IS NULL THEN 1 ELSE 0 END) AS null_thread_ts,
       SUM(CASE WHEN first_response_at_utc IS NULL THEN 1 ELSE 0 END) AS null_first_response
FROM escalation
GROUP BY status
ORDER BY escalations DESC;

\echo ''
\echo '=== P07: rubric versions in use vs rubric_weight coverage ==='
SELECT rubric_version, COUNT(*) AS audits
FROM note_audit
GROUP BY rubric_version
ORDER BY rubric_version;

\echo ''
SELECT rubric_version, dimension, weight, pass_threshold, effective_from
FROM rubric_weight
ORDER BY rubric_version, dimension;

\echo ''
\echo '=== P08: rubric weight sums per version (do they add to 1.0?) ==='
SELECT rubric_version,
       COUNT(*)      AS dimensions,
       SUM(weight)   AS weight_total,
       MIN(pass_threshold) AS min_threshold,
       MAX(pass_threshold) AS max_threshold
FROM rubric_weight
GROUP BY rubric_version
ORDER BY rubric_version;

\echo ''
\echo '=== P09: sla_config effective-date overlap check ==='
SELECT product_line, priority, COUNT(*) AS config_rows
FROM sla_config
GROUP BY product_line, priority
ORDER BY product_line, priority;

\echo ''
\echo '=== P10: note timestamp range and NULL delivery ==='
SELECT MIN(submitted_at_utc) AS earliest_submit,
       MAX(submitted_at_utc) AS latest_submit,
       SUM(CASE WHEN delivered_at_utc IS NULL THEN 1 ELSE 0 END) AS null_delivered,
       SUM(CASE WHEN word_count IS NULL THEN 1 ELSE 0 END)       AS null_word_count
FROM note;