UPDATE escalation
SET status = 'POSTED'
WHERE status = 'POSTING'
  AND EXISTS (
    SELECT 1 FROM escalation_repost_audit a
    WHERE a.escalation_id = escalation.escalation_id
      AND a.outcome = 'SUCCESS'
  )
RETURNING escalation_id, status