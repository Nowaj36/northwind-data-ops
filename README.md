# Northwind Ambient Ops — BI Engineer assessment

Reconciliation of the Q2 FY26 Ambient Ops Review, a triage workbench for the
Audit Triage Lead, and a recovery workflow for escalations that never reached
Slack.

**Headline:** the Q2 memo's numbers do not survive inspection. Audit pass rate
is **76.8%**, not 79.9%. The delivery SLA breach rate was measured over **147
notes out of 5,506** — 2.7% coverage — and is 10.4% over the real population,
not 12.8%. Of 149 "open" escalations, **43 were never posted to Slack at all**.
Of 28 flagged volume anomalies, **26 were weekends** and 2 were real.

Decision A (remediation) is justified but under-scoped. **Decision B (the
recognition award and coaching plans) should not be executed** — three named
individuals are misplaced, including one inactive employee about to receive a
documented coaching plan. Details in [RECONCILIATION.md](RECONCILIATION.md).

---

## Deliverables

| Document | What's in it |
|---|---|
| [RECONCILIATION.md](RECONCILIATION.md) | Table profiling, four variance waterfalls, 18 defects, the two business questions, what I did not check |
| [UX_RATIONALE.md](UX_RATIONALE.md) | Operator time budget, R2 interaction math, two rejected layouts, the requirement I did not meet |
| [DECISIONS.md](DECISIONS.md) | Five stakeholder conflicts from Appendix B — what I chose and what I gave up |
| [AI_USAGE.md](AI_USAGE.md) | Where AI was used, and where I overrode it |
| [docs/adr/](docs/adr/) | Three ADRs: quarter definition, explicit commit, claim-then-process |

**Retool app:** Ambient Ops Triage Workbench — released.
**Retool workflow:** Stranded Escalation Recovery — released, version 3.0.1.
**Video:** _(link)_

> **Retool access.** The free tier does not expose per-app or per-workflow
> access controls — "Access controls isn't available on your plan." I could not
> add reviewers directly. Both the app and the workflow are built and released
> in my workspace, and I can screen-share either during the live review. If a
> direct invite is required, tell me and I will rebuild in an org account you
> provide.

---

## Setup

Prerequisites: `psql` (16+), a free Postgres (this was built on Supabase), and
a Retool account.

**1. Create the schema and load the data.**

```bash
psql -d "<connection string>" -f schema.sql
psql -d "<connection string>"
```

Then, from inside `psql`, with the seven CSVs in `data/`:

```sql
\copy note           FROM 'data/note.csv'           WITH (FORMAT csv, HEADER true)
\copy note_audit     FROM 'data/note_audit.csv'     WITH (FORMAT csv, HEADER true)
\copy clinician      FROM 'data/clinician.csv'      WITH (FORMAT csv, HEADER true)
\copy mds            FROM 'data/mds.csv'            WITH (FORMAT csv, HEADER true)
\copy sla_config     FROM 'data/sla_config.csv'     WITH (FORMAT csv, HEADER true)
\copy rubric_weight  FROM 'data/rubric_weight.csv'  WITH (FORMAT csv, HEADER true)
\copy escalation     FROM 'data/escalation.csv'     WITH (FORMAT csv, HEADER true)
```

Expected counts: note 6,235 · note_audit 1,780 · clinician 64 · mds 34 ·
sla_config 8 · rubric_weight 14 · escalation 533.

**2. Create the tables this project adds.**

```bash
psql -d "<connection string>" -f src/queries/retool/triage_decision.sql
psql -d "<connection string>" -f src/queries/part3/escalation_repost_audit.sql
```

**3. Reproduce the findings.**

```bash
psql -d "<connection string>" -f src/queries/profiling/run_all_profiling.sql
```

Every waterfall query in `src/queries/waterfall/` carries the result it produced
in a header comment. Run them in any order; they are read-only.

**4. Wire up Retool.** Add the Postgres instance as a resource, then point the
app's `getTriageQueue` query and the workflow's blocks at it. The SQL for both
lives in `src/queries/` and `src/workflow/`.

---

## Repository layout

```
├── RECONCILIATION.md              Part 1
├── UX_RATIONALE.md                Part 2
├── DECISIONS.md                   Part 4.5 — stakeholder conflicts
├── AI_USAGE.md                    Part 4.6
├── SUBMISSION_CHECKLIST.md
├── schema.sql                     Source DDL, as shipped
├── docs/
│   └── adr/                       Three ADRs
├── notes/                         Working notes and raw query output
├── src/
│   ├── queries/
│   │   ├── profiling/             Grain and key-uniqueness checks
│   │   ├── waterfall/             One file per headline metric
│   │   ├── retool/                The triage queue query (R10)
│   │   └── part3/                 Recovery workflow: DDL, detection,
│   │                              failure-pattern analysis
│   └── transformers/
├── tests/
└── data/                          The seven source CSVs

Every number in the written deliverables comes from a query in `src/queries/`,
and each query file records the result it produced when run.

---

## What the three parts found

**Part 1.** The provided queries reproduce the memo exactly, so the memo is not
a transcription error — the queries are wrong. Eighteen defects, all quantified.
The two that matter most share a root cause: rubric v2 took effect mid-quarter
on 2026-05-15, raising the pass threshold from 0.85 to 0.90 and reweighting four
of seven dimensions, and **the ETL was never updated for either change**. It
scores v2 audits with v1 weights (234 audits, understated by 0.0216 on average)
and judges them against the v1 threshold (143 audits marked PASS that v2 fails).

These two corrections move the pass rate in *opposite* directions — −8.1 and
+5.4 points. Fixing only the threshold lands at 71.6%, which is **further from
the truth than the original 79.9%**. A partial fix is worse than no fix.

**Part 2.** A single-screen workbench, queue derived from the corrected logic,
with a provenance panel showing the rubric version, the threshold that applied
to that note, all seven sub-scores, and the SLA target in force on the note's
own date rather than today's. Nine of ten hard requirements met; R3 (keyboard
operation) is not, and why is in UX_RATIONALE.md §4.

**Part 3.** The 43 stranded escalations name their own cause: every one carries
`slack_api:ratelimited (HTTP 429)` with `attempt_count = 1`, clustered into two
windows — 24 records on 2026-05-07 between 14:00 and 14:05, and 19 on
2026-06-11 between 09:00 and 09:04. The pipeline took a 429 as terminal and
never retried. The recovery workflow claims records atomically
(`FOR UPDATE SKIP LOCKED` plus a `PENDING_POST → POSTING → POSTED` transition),
posts them one per second, and writes an audit row per attempt. Verified: 43
stranded → 43 posted → 43 audit rows → 0 duplicates, with repeat runs posting
nothing.

---

## Where I stopped, and what I would do next

I stopped at roughly ten focused hours across four days. Retool's version
history shows a wider wall-clock window; that includes breaks, not continuous
work.

Not built, in the order I would build them:

1. **W6 hardening — a reclaim path for stale `POSTING` rows.** The claim
   pattern is safe against concurrency but not against a crashed run: a workflow
   that dies mid-batch strands records in `POSTING` with nothing to pick them
   up. That is the same silent-failure shape as the bug being fixed, relocated.
   Needs a `claimed_at` column and a reclaim predicate. ~30 min.
2. **W4 — jitter and exponential backoff.** Currently a fixed 1s iteration
   delay, which holds the ≤1 req/sec budget but does nothing on 429/5xx.
   `delay = min(2^attempt * 1000, 30000)` plus up to 500ms of jitter, retrying
   only 429 and 5xx and letting 4xx fail fast. Jitter matters specifically here:
   the outage being recovered from hit 43 records in two tight windows, and
   identical retry timing across a fleet reproduces the herd that caused it.
   ~30 min.
3. **W5 — dead-lettering.** After three attempts, `status = 'DEAD_LETTER'` with
   the last HTTP status, surfaced as a second queue in the workbench. N=3
   because the observed failure is transient rate limiting, which three attempts
   across ~7 seconds of backoff clears; a malformed payload fails identically
   three times and belongs in front of a human rather than in a retry loop.
   ~30 min.
4. **Reversible dispositions.** The unique index on `triage_decision(note_id)`
   that makes bulk commit idempotent also blocks corrections, which contradicts
   Compliance's requirement (R-04). Fix is a partial unique index on
   `(note_id) WHERE superseded_at_utc IS NULL` — the same pattern already used
   in `escalation_repost_audit`. This is a bug, not a trade; see DECISIONS.md
   Conflict 4. ~20 min.
5. **Unit tests and CI.** The four boundaries named in 6.3 — the Chicago
   business-day boundary, the deduplication rule, the effective-dated lookup,
   and the idempotency key. Each has an obvious edge case: a note at 23:30
   Chicago on 30 June, a `note_id` whose two ingestions share a timestamp, a
   note submitted exactly on 2026-05-15, and a repeat submit of an identical
   disposition. ~1 hr.

The recovery is safe to run today — it will not duplicate or corrupt — but it
is not yet safe to leave unattended.

---

## What is wrong with this assessment

Forty of a hundred points ride on Retool. I had not used it before this week,
and a real share of my ten hours went to learning where things live — scope
boundaries, event-handler ordering, why keyboard shortcuts could not reach my
own components. None of that told you whether I can reason about data.

Retool is learnable in a week. Noticing that a pass rate fell because the rubric
changed rather than because people got worse is not.

I would keep Part 2's thinking and drop its tooling: hand me a static mockup of
a triage screen and ask which three columns I would cut and why, what the
operator sees when the query fails, and what a wrong disposition costs. That
tests operator judgment in an hour instead of six, and it cannot be passed by
someone who simply already knows the tool.