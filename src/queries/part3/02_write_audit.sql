INSERT INTO escalation_repost_audit
  (escalation_id, attempt_no, http_status, response_body, outcome, run_id)
SELECT
  src.rec->>'escalation_id',
  1,
  200,
  left(coalesce(resp.rec::text, ''), 500),
  'SUCCESS',
  {{ runContext.data.run_id }}
FROM jsonb_array_elements({{ JSON.stringify(findStranded.data) }}::jsonb)
     WITH ORDINALITY AS src(rec, ord)
JOIN jsonb_array_elements({{ JSON.stringify(postToSlack.data) }}::jsonb)
     WITH ORDINALITY AS resp(rec, ord)
  ON src.ord = resp.ord
ON CONFLICT DO NOTHING