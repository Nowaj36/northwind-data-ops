# ADR 003 — Claim-then-process for the stranded escalation recovery

## Status

Accepted

## Context

43 escalations sat in `PENDING_POST` with a null `slack_thread_ts` — created in
the database, never posted to Slack, never worked by anyone. The failure
pattern names its own cause: every one carries
`last_api_error = 'slack_api:ratelimited (HTTP 429)'`, `attempt_count = 1`, and
they cluster into two tight windows — 2026-05-07 14:00–14:05 (24 records) and
2026-06-11 09:00–09:04 (19 records). The pipeline attempted once, took a 429 as
terminal, and moved on. Nothing retried and nothing alerted.

The recovery workflow must not repeat that failure or invent new ones. Two
requirements carry the weight (W3, W6): five consecutive runs must produce the
same end state with no duplicate posts, and a run must be safe to start while
another is still in flight.

The naive shape — `SELECT` the stranded records, POST each, `UPDATE` the ones
that succeeded — fails both. Two runs starting seconds apart both see the same
43 rows and both post them.

## Options considered

**A. Advisory lock around the whole run.** `pg_try_advisory_lock()` at the
start; a second run fails to acquire and exits. Simple to explain and easy to
verify. But it serialises the entire recovery — a long run blocks a short one
entirely, and if a run dies without releasing, the lock's fate depends on
connection lifetime, which in a hosted workflow runner is not something I
control.

**B. Deduplicate on write only.** Let both runs post, and rely on a unique
constraint in the audit table to reject the second write. The database stays
consistent, but *the duplicate HTTP post already happened* — and the whole
point of W2 is that the post is a real side effect. Consistent audit rows do
not un-notify a Slack channel.

**C. Claim-then-process.** Atomically claim a batch of records in the same
statement that selects them, so a concurrent run cannot see what has been
claimed. Process only what this run owns.

## Decision

**C.** The detection block does not `SELECT` — it `UPDATE`s and returns:

```sql
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
```

Three mechanisms, each covering a different window:

**`FOR UPDATE SKIP LOCKED`** protects the instant between select and update. A
concurrent transaction skips locked rows rather than waiting on them, so two
runs starting simultaneously partition the work instead of duplicating it.

**The `PENDING_POST → POSTING` transition** protects everything after the lock
is released. A claimed record no longer matches the `status = 'PENDING_POST'`
predicate, so a run starting a second later does not see it at all.

**`NOT EXISTS` against a SUCCESS audit row** protects across runs and over
time. Anything already posted is permanently out of scope, which is what makes
run five identical to run two.

Underneath, a partial unique index makes the guarantee structural rather than
procedural:

```sql
CREATE UNIQUE INDEX idx_repost_success_once
  ON escalation_repost_audit (escalation_id)
  WHERE outcome = 'SUCCESS';
```

At most one SUCCESS row per escalation can exist. Failed attempts are
unconstrained, so retry history is preserved. Even if the application logic
were wrong, the database would refuse a second success.

The `LEFT JOIN` form of the exclusion had to become `NOT EXISTS`: Postgres
rejects `FOR UPDATE` applied to the nullable side of an outer join. The
semantics are identical; only the lockable relation changes.

## Consequences

- **W3 verified empirically.** 43 stranded → 43 posted → 43 audit rows → 0
  duplicate audit rows → 0 remaining stranded. `successful_reposts` and
  `distinct_escalations` both read 43 in the reconciliation query, which is the
  direct evidence: if any record had posted twice they would differ.
- **A crashed run strands records in `POSTING`.** This is the pattern's real
  cost. There is no reaper, so a workflow that dies mid-batch leaves rows in a
  state nothing picks up — the same silent-failure shape as the original bug,
  in a new place. Production needs either a timestamp on the claim plus a
  reclaim predicate (`status = 'POSTING' AND claimed_at < now() - interval '10
  minutes'`), or `attempt_count`-based expiry. `escalation` has no `updated_at`
  column, so this needs a schema change and is not in this submission.
- **`markPosted` is scoped by claim state, not by run identity.** It updates
  `WHERE status = 'POSTING' AND EXISTS (...SUCCESS audit...)`. Records claimed
  by another run are already `POSTED` and unaffected — the claim itself provides
  run isolation, so no run identifier is needed.

  This replaced a `run_id`-based version, and the reason is worth recording. A
  JS block generated a `run_id` per run and `markPosted` filtered on it. The
  audit table showed every row across four separate runs carrying the *first*
  run's ID — the block was not re-executing, so `markPosted`'s `WHERE run_id =
  ...` matched every historical row rather than this run's. Nothing broke
  visibly because every record happened to succeed; had one failed, it would
  have been marked `POSTED` with a `FAILED` audit row. The fix was removing the
  dependency rather than patching the block, on the grounds that the claim state
  already carried the isolation the run identifier was being asked to provide.
  `run_id` remains on the audit table for tracing, no longer as a correctness
  mechanism.
- **Batch size is capped at 50 per run** by the `LIMIT`, which bounds blast
  radius and keeps a run's duration predictable at one request per second.
- **Rate limiting is a fixed 1s iteration delay, not adaptive.** Jitter and
  exponential backoff on 429/5xx (W4) and dead-lettering after N attempts (W5)
  are not implemented; see the README. Jitter matters here specifically — the
  outage being recovered from hit 43 records in two tight windows, and a fleet
  retrying on identical timing reproduces the herd that caused it.