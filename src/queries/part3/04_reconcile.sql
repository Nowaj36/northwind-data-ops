SELECT
  (SELECT COUNT(*) FROM escalation
    WHERE status = 'PENDING_POST' AND slack_thread_ts IS NULL)      AS remaining_stranded,
  (SELECT COUNT(*) FROM escalation_repost_audit
    WHERE outcome = 'SUCCESS')                                      AS successful_reposts,
  (SELECT COUNT(DISTINCT escalation_id) FROM escalation_repost_audit
    WHERE outcome = 'SUCCESS')                                      AS distinct_escalations,
  (SELECT COUNT(*) FROM (
      SELECT escalation_id FROM escalation_repost_audit
      WHERE outcome = 'SUCCESS'
      GROUP BY escalation_id HAVING COUNT(*) > 1) d)                AS duplicate_reposts,
  (SELECT COUNT(*) FROM escalation WHERE status = 'POSTED')         AS marked_posted