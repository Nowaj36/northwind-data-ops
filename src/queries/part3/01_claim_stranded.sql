WITH claimed AS (
  UPDATE escalation
  SET status = 'POSTING',
      attempt_count = COALESCE(attempt_count, 0) + 1
  WHERE escalation_id IN (
    SELECT e.escalation_id
    FROM escalation e
    WHERE e.status = 'PENDING_POST'
      AND e.slack_thread_ts IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM escalation_repost_audit a
        WHERE a.escalation_id = e.escalation_id
          AND a.outcome = 'SUCCESS'
      )
    ORDER BY e.created_at_utc
    FOR UPDATE SKIP LOCKED
    LIMIT 50
  )
  RETURNING escalation_id, note_id, slack_channel, created_at_utc,
            assignee_mds_id, attempt_count
)
SELECT * FROM claimed ORDER BY created_at_utc