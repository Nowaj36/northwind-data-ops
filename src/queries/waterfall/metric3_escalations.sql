-- METRIC 3 — baseline: 149 open, 49.5 min
SELECT
    COUNT(*)                                                          AS open_escalations,
    ROUND(AVG(EXTRACT(EPOCH FROM (e.first_response_at_utc - e.created_at_utc))/60.0)::numeric, 1)
                                                                      AS avg_minutes_to_first_response,
    MIN(e.created_at_utc)                                             AS oldest_open
FROM escalation e
WHERE e.status <> 'RESOLVED'
  AND e.created_at_utc BETWEEN TIMESTAMP '2026-04-01' AND TIMESTAMP '2026-06-30';


-- METRIC 3 — breakdown: OPEN 106 / PENDING_POST 43 (43 never_posted, 43 no_response)
SELECT
  e.status,
  COUNT(*)                                                          AS escalations,
  SUM(CASE WHEN e.slack_thread_ts       IS NULL THEN 1 ELSE 0 END)  AS never_posted,
  SUM(CASE WHEN e.first_response_at_utc IS NULL THEN 1 ELSE 0 END)  AS no_first_response,
  SUM(CASE WHEN e.assignee_mds_id       IS NULL THEN 1 ELSE 0 END)  AS unassigned
FROM escalation e
WHERE e.status <> 'RESOLVED'
  AND e.created_at_utc BETWEEN TIMESTAMP '2026-04-01' AND TIMESTAMP '2026-06-30'
GROUP BY e.status
ORDER BY escalations DESC;


-- METRIC 3 — before Q2 still open: 6 | after Q2 still open: 8
SELECT COUNT(*) AS open_but_created_before_q2
FROM escalation
WHERE status = 'OPEN'
  AND created_at_utc < TIMESTAMP '2026-04-01';


-- ---------------------------------------------------------------------
-- EVIDENCE — open escalations created after the quarter closed
-- (the replica carries data to 2026-07-06)
-- Result: OPEN | 8
-- ---------------------------------------------------------------------
SELECT
  status,
  COUNT(*) AS escalations
FROM escalation
WHERE status <> 'RESOLVED'
  AND created_at_utc > TIMESTAMP '2026-06-30'
GROUP BY status;


-- METRIC 3 — TRUE: 120 open, 43 stranded
SELECT
  SUM(CASE WHEN status = 'OPEN'                                  THEN 1 ELSE 0 END) AS genuinely_open,
  SUM(CASE WHEN status = 'PENDING_POST'
            AND slack_thread_ts IS NULL                          THEN 1 ELSE 0 END) AS stranded_never_posted,
  SUM(CASE WHEN status = 'RESOLVED'                              THEN 1 ELSE 0 END) AS resolved,
  COUNT(*)                                                                          AS total_escalations
FROM escalation;


-- ---------------------------------------------------------------------
-- TRUE VALUE — open escalations by when they were raised, for context
-- Result: before Q2 = 6 · in Q2 = 106 · after Q2 = 8 · total = 120
-- ---------------------------------------------------------------------
SELECT
  CASE
    WHEN created_at_utc <  TIMESTAMP '2026-04-01' THEN 'before Q2'
    WHEN created_at_utc >  TIMESTAMP '2026-06-30' THEN 'after Q2'
    ELSE 'in Q2'
  END                          AS raised_when,
  COUNT(*)                     AS open_escalations,
  MIN(created_at_utc)          AS oldest,
  MAX(created_at_utc)          AS newest
FROM escalation
WHERE status = 'OPEN'
GROUP BY 1
ORDER BY MIN(created_at_utc);


-- ---------------------------------------------------------------------
-- TRUE VALUE — time to first response, over the population that actually
-- has one. Reported as 49.5 min against a denominator of 149; it is an
-- average over 106 rows.
-- ---------------------------------------------------------------------
SELECT
  COUNT(*)                                                          AS open_escalations,
  COUNT(first_response_at_utc)                                      AS with_first_response,
  ROUND(AVG(EXTRACT(EPOCH FROM (first_response_at_utc - created_at_utc))/60.0)::numeric, 1)
                                                                    AS avg_minutes_to_first_response
FROM escalation
WHERE status = 'OPEN';