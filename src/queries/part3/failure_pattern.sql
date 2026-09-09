-- Failure pattern: are all stranded escalations clustered in time?
SELECT
  DATE_TRUNC('minute', created_at_utc) AS minute_bucket,
  COUNT(*) AS stranded,
  MIN(created_at_utc) AS first_seen,
  MAX(created_at_utc) AS last_seen,
  MIN(attempt_count) AS min_attempts,
  MAX(attempt_count) AS max_attempts,
  STRING_AGG(DISTINCT last_api_error, ' | ') AS errors
FROM escalation
WHERE status = 'PENDING_POST' AND slack_thread_ts IS NULL
GROUP BY 1
ORDER BY 1;