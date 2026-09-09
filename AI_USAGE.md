# AI_USAGE

## Tooling

Claude (Anthropic) — used interactively throughout, in a chat session, for
SQL drafting, defect hypothesis generation, Retool guidance, and prose editing.

Sourcery — a GitHub App that auto-generates PR summaries. Left enabled; its
changelog-style overview appears on the PR alongside my own line-level review
comments. It did not review my logic, and I did not treat it as review.

## Where AI was used

| Area | Use | My role |
|---|---|---|
| Table profiling | Drafted the profiling query set — grain, key uniqueness, NULL and status distributions | Specified what to profile; ran every query; interpreted the results |
| Defect hypotheses | Generated a list of suspected defects from `schema.sql` and `PROVIDED_QUERIES.sql` before any data was loaded | Treated as hypotheses only. Each was confirmed or rejected against the data; the ones in RECONCILIATION.md are the ones that survived |
| Waterfall SQL | Drafted the incremental correction queries — dedup CTE, effective-dated joins, timezone conversion, composite recompute | Ran each, checked the deltas reconciled, and rejected results whose arithmetic did not tie |
| Retool build | Step-by-step guidance on components, bindings, event handlers, and the workflow blocks | Every click was mine. Debugged the failures myself against Retool's actual behaviour, which is where most of the corrections below came from |
| Part 3 workflow | Drafted the claim query, the audit DDL, and the reconciliation query | Ran them, found the run_id defect below, and changed the design |
| Prose | Drafted and tightened the markdown deliverables | Supplied every number; verified each against a query I ran |

## Where AI was NOT used

- Retool app layout — built by hand, per the assessment constraint. No
  Retool AI or app-generation features were used at any point.
- Any figure in a deliverable. Every number came from a query I executed
  against my own Postgres instance and is reproducible from `src/queries/`.

## Where I overrode or corrected it

### 1. The run_id design was wrong, and the data showed it

For Part 3, the suggested design gave each workflow run an identifier from a JS
block, and `markPosted` filtered on it:

```sql
WHERE run_id = {{ runContext.data.run_id }} AND outcome = 'SUCCESS'
```

It looked correct and the workflow ran clean. I checked the audit table anyway:

```sql
SELECT run_id, COUNT(*), MIN(posted_at_utc) FROM escalation_repost_audit
GROUP BY run_id ORDER BY MIN(posted_at_utc) DESC;
```

Four separate runs, and rows written twenty minutes apart all carried the
first run's identifier. The JS block was not re-executing between runs. So
`markPosted`'s `WHERE run_id = ...` was matching every historical row, not this
run's — it had been updating records other runs owned, for as long as it had
existed.

Nothing broke visibly because every record happened to succeed. Had one failed,
it would have been marked `POSTED` while its audit row said `FAILED` — silent
divergence between the state table and the audit trail, which is exactly the
class of bug Part 1 was about.

I did not patch the JS block. The claim pattern already provides run isolation:
a record this run owns is in `POSTING`, and records other runs owned are already
`POSTED`. So I removed the run identifier from the correctness path entirely:

```sql
UPDATE escalation SET status = 'POSTED'
WHERE status = 'POSTING'
  AND EXISTS (SELECT 1 FROM escalation_repost_audit a
              WHERE a.escalation_id = escalation.escalation_id
                AND a.outcome = 'SUCCESS')
```

`run_id` stays on the audit table for tracing. It is no longer load-bearing.
Recorded in ADR 003.

### 2. A timing patch I accepted, then replaced

An earlier bug: committing a disposition wrote NULLs, because the dropdown-clear
actions fired from the button's click handler alongside the query trigger, and
Retool fires click handlers in parallel rather than in sequence.

The first fix offered was a `debounce` plus an `Only run when` guard on the
clear actions. I applied it and it worked — but it worked by *waiting long
enough*, which is a guess about how slow the insert is, not a guarantee about
ordering. I kept looking and moved the clear actions into the query's own
success handler, where they cannot run before the insert returns.

I am recording this one because the patch passed the test. Had I stopped at the
green result, the bug would have shipped and reappeared the first time the
database was slow.

### 3. A suggestion that solved one requirement and broke another

To make bulk commit safe to double-submit (R8), the suggested fix was a unique
index on `triage_decision(note_id)` with `ON CONFLICT DO NOTHING`. It works, and
I shipped it.

Reading Appendix B afterwards, Compliance requires that every state change be
*"attributable to a named user, timestamped, and reversible"* (R-04). That
index makes the table append-once: a correction to a disposition is rejected,
not recorded. I had satisfied idempotency by making the data immutable, and
broken reversibility doing it.

Neither I nor the tool connected those two requirements at the time they were
each being handled — they arrived hours apart, in different parts of the work.
The fix is a partial unique index on `(note_id) WHERE superseded_at_utc IS NULL`,
the same pattern I had already used in `escalation_repost_audit`. It is
specified in DECISIONS.md Conflict 4 and not implemented; I ran out of budget.

The lesson I take from it is not about the tool. Requirements from different
stakeholders collide in the schema, and nothing surfaces that collision except
reading them against your own DDL.

### 4. Smaller corrections

- Column-name casing. Bindings were drafted as
  `TriageQueue.selectedRow.SCORE_ACCURACY` because Retool's output panel
  displays column headers in uppercase. The actual properties are lowercase —
  `JSON.stringify(TriageQueue.selectedRow)` showed it in a second. Display
  formatting is not the data contract.
- `FOR UPDATE` on an outer join. The claim query was first drafted with a
  `LEFT JOIN ... WHERE a.escalation_id IS NULL` exclusion. Postgres rejects
  `FOR UPDATE` applied to the nullable side of an outer join, so I rewrote it
  as `NOT EXISTS`. Same semantics, and only `escalation` is locked.
- `fetch` in Retool Workflows. The loop was drafted as a JS block calling
  `fetch`. Every iteration failed with `ReferenceError: fetch is not defined`.
  Switched to the REST API loop runner, which cost the per-request status
  capture the audit schema was designed for — noted as a limitation rather than
  papered over.

### 5. The verification that kept a correct fix

Not an override, but the same discipline. The clinician SCD fix
(`AND c.is_current_record = true`) dropped 125 notes. That felt too large to
accept — a filter that big could equally mean it was silently excluding notes
whose clinician had no current row, which would be a new bug wearing the costume
of a fix.

Three checks before keeping it: the four duplicated clinicians produce exactly
250 joined rows in-quarter (250 ÷ 2 = 125, matching the delta); every one of the
60 clinicians has exactly one current record; no `note.clinician_id` is missing
from the dimension. The fix survived because the arithmetic tied, not because
it looked plausible.

## Fingerprints

This submission was written with AI assistance and says so. Where phrasing came
from a model I edited it. Where numbers appear they are mine, and the query that
produced them is in the repo. Every defect in RECONCILIATION.md was confirmed
against the data before it was written down, and the three above are the places
where confirming it changed the answer.