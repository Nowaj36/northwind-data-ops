# RECONCILIATION — Q2 FY26 Ambient Ops Review

Every figure below is reproducible from a query in `src/queries/`. Query file
references are given per section. Comments inside each query file record the
result it produced when run.

---

## 0. Scope and definitions

"The quarter" = Q2 FY26 = 2026-04-01 through 2026-06-30 inclusive, on the
America/Chicago business day.

Defence: Ops runs on the Chicago business day, but every `*_utc` column is a
naive UTC timestamp. A note submitted at 2026-06-30 23:30 Chicago is
2026-07-01 04:30 UTC — the same operational day to the people whose numbers
these are. The quarter is therefore evaluated as:

```sql
(submitted_at_utc AT TIME ZONE 'UTC' AT TIME ZONE 'America/Chicago')::date
  BETWEEN DATE '2026-04-01' AND DATE '2026-06-30'
```

The provided queries instead use `BETWEEN TIMESTAMP '2026-04-01' AND
TIMESTAMP '2026-06-30'`, a UTC window that terminates at 2026-06-30
00:00:00 — excluding the whole of 30 June. See ADR 001 for the full
decision record, including the DST rationale for converting via the timezone
database rather than a fixed offset.

---

## 1. Profile before fixing — table grain and key uniqueness

Query file: `src/queries/profiling/run_all_profiling.sql`

| Table | Rows | Declared key | Actual uniqueness | Notes |
|---|---:|---|---|---|
| `note` | 6,235 | `note_id` | Not unique — 6,173 distinct | 62 note_ids appear twice (re-ingestion) |
| `note_audit` | 1,780 | `audit_id` | Unique (1,780 / 1,780) | One audit per note; 0 repeat audits |
| `clinician` | 64 | `clinician_id` | Not unique — 60 distinct | SCD type 2; 4 clinicians carry a stale row |
| `mds` | 34 | `mds_id` | Unique | `mds_name` is not — one name shared by two IDs |
| `sla_config` | 8 | `config_id` | Unique | 2 effective-dated rows per product/priority |
| `rubric_weight` | 14 | — | `(rubric_version, dimension)` | v1 and v2, 7 dimensions each, weights sum to 1.00 |
| `escalation` | 533 | `escalation_id` | Unique | 370 RESOLVED · 120 OPEN · 43 PENDING_POST |

### Where the data disagrees with a naive reading

- `note` is not one row per note. The grain is one row per *ingestion*.
  `ingestion_id` carries a version suffix (`IG-000651-1`, `IG-000651-2`).
  Any join to `note` on `note_id` without deduplication double-counts.
- `clinician` is a slowly-changing dimension. `record_effective_from` /
  `record_effective_to` / `is_current_record` exist, but no provided query
  filters on them. Verified: all 60 clinicians have exactly one
  `is_current_record = true` row, so filtering on it orphans nobody.
- `sla_config` is effective-dated and changed mid-quarter (2026-05-15).
  Every product_line/priority pair has 2 rows. Joining without a date
  predicate fans out and can apply a target that was not in force.
- `rubric_weight` changed mid-quarter too (v2 effective 2026-05-15):
  both the weights and the pass threshold moved (0.85 → 0.90).
- `composite_score` and `pass_fail` on `note_audit` are ETL-derived, per
  the schema comment — they are pipeline outputs, not source data, and both
  are wrong for v2 audits (see D4 and D6).
- `mds_name` is not a key. Two active people share the name "Domingo,
  Rafael" (MD-206, MD-227). Grouping by name instead of `mds_id` merges them.
- `mds.status` is not ACTIVE for everyone on the leaderboard. Two
  INACTIVE staff (MD-201, MD-218) still have Q2 notes attributed to them.
- `word_count` is nullable and NULL ≠ 0 (152 NULLs overall, 134 in-quarter).
  The provided leaderboard query coerces with `COALESCE(word_count, 0)`.
- `escalation.status = 'PENDING_POST'` means `slack_thread_ts IS NULL` —
  the escalation was never posted. All 43 such rows also have no
  `first_response_at_utc`. They are not "open" in any operational sense;
  nobody has seen them.

---

## 2. Metric 1 — Notes audited and audit pass rate

Query file: `src/queries/waterfall/audit_pass_rate.sql`

Reported: 1,705 notes · 79.9% pass · 0.9055 avg composite
True: 1,566 notes · 76.8% pass · 0.9161 avg composite

### Variance waterfall

| # | Correction applied | Notes | Pass rate | Δ notes | Δ pass rate |
|---|---|---:|---:|---:|---:|
| 0 | Reported figure | 1,705 | 79.9% | — | — |
| 1 | Exclude void notes (`is_void = true`) | 1,687 | 79.9% | −18 | 0.0 |
| 2 | Clinician SCD fan-out fix (current record only) | 1,562 | 79.8% | −125 | −0.1 |
| 3 | Deduplicate `note` to latest ingestion per `note_id` | 1,546 | 79.7% | −16 | −0.1 |
| 4 | Evaluate pass/fail against the effective rubric threshold | 1,546 | 71.6% | 0 | −8.1 |
| 5 | Define the quarter on the America/Chicago business day | 1,566 | 71.4% | +20 | −0.2 |
| 6 | Recompute composite from the effective rubric weights | 1,566 | 76.8% | 0 | +5.4 |

### Defects behind each row

D1 — Void notes counted (row 1, −18 notes).
90 notes carry `is_void = true` (35 DUPLICATE_ENCOUNTER, 33 WRONG_PATIENT,
22 CLINICIAN_RETRACTED). No provided query excludes them.

D2 — Clinician SCD fan-out (row 2, −125 notes).
`JOIN clinician c ON c.clinician_id = n.clinician_id` with no effective-date
or current-record predicate. Four clinicians (CL-1004, CL-1018, CL-1029,
CL-1045) hold two rows each, so their notes are counted twice.
*Verified:* those four clinicians produce 250 joined rows in-quarter;
250 ÷ 2 = 125, matching the delta exactly. All 60 clinicians have exactly one
current record and no note references a clinician_id absent from the
dimension, so the fix removes duplication only — it drops no real note.

D3 — Note re-ingestion duplicates (row 3, −16 notes).
62 `note_id`s appear twice, always as `-1` / `-2` ingestion versions sharing
`submitted_at_utc`, `encounter_id`, `clinician_id` and `mds_id`, but with a
later `ingested_at_utc` and usually a revised `word_count` and
`delivered_at_utc`. Dedup rule: keep the row with the greatest
`ingested_at_utc` per `note_id`.
*Verified:* ordering by `ingested_at_utc` and ordering by the numeric
`ingestion_id` suffix select the same row for all 62 duplicated note_ids
(0 disagreements) — the rule is unambiguous.

D4 — ETL applied the wrong pass threshold (row 4, −8.1 points).
Rubric v2 raised the threshold from 0.85 to 0.90 effective 2026-05-15. The
stored `pass_fail` still reflects 0.85:

| rubric_version | threshold | audits | stored PASS | recomputed PASS | wrongly PASS |
|---|---:|---:|---:|---:|---:|
| v1 | 0.85 | 851 | 751 | 751 | 0 |
| v2 | 0.90 | 929 | 677 | 534 | 143 |

v1 is exact. All 143 discrepancies sit in v2, and all run one direction — the
pipeline never picked up the new threshold.

D5 — Quarter boundary (row 5, +20 notes).
`BETWEEN ... AND TIMESTAMP '2026-06-30'` ends at midnight, excluding all
audited notes submitted during 30 June; the window is also UTC while Ops
runs on America/Chicago. Correcting both nets +21 notes entering (chiefly
30 June) and −1 leaving (a note just after UTC midnight on 1 April that
belongs to the Chicago day of 31 March), for a net of +20.

D6 — ETL computed v2 composites with v1 weights (row 6, +5.4 points).
Recomputing `composite_score` from `rubric_weight` for each audit's own
version:

| rubric_version | audits | matches | mismatches | avg (stored − recomputed) |
|---|---:|---:|---:|---:|
| v1 | 851 | 782 | 69 | 0.0000 |
| v2 | 929 | 695 | 234 | −0.0216 |

v1's 69 mismatches average to zero — rounding noise. v2's 234 are
systematically low by 0.0216, consistent with v1 weights (accuracy 0.30,
completeness 0.20, formatting 0.10, plan 0.15) being applied to v2 audits
(0.35 / 0.25 / 0.05 / 0.10).

### ⚠️ Two corrections move the pass rate in opposite directions

D4 moves the pass rate −8.1 points. D6 moves it +5.4 points. Same root
cause — the ETL was never updated for rubric v2 — but opposite effects. A
partial fix is worse than no fix:

| State | Pass rate | Distance from truth (76.8%) |
|---|---:|---:|
| Original query | 79.9% | 3.1 pts |
| D4 fixed, D6 missed | 71.6% | 5.2 pts |
| Both fixed (true) | 76.8% | — |

---

## 3. Metric 2 — Delivery SLA breach rate

Query file: `src/queries/waterfall/sla_breach_rate.sql`

Reported: 12.8% breach · 296 rows · median 18.5 min
True: 10.4% breach · 5,449 notes · median 18.1 min

### Variance waterfall

| # | Correction applied | Population | Breach rate | Median |
|---|---|---:|---:|---:|
| 0 | Reported figure | 296 rows | 12.8% | 18.5 min |
| 1 | Drop the escalation join; dedup, exclude void, effective-date the SLA lookup, Chicago quarter | 5,449 notes | 10.4% | 18.1 min |

### Defects

D7 — LEFT JOIN neutralised by the WHERE clause (population collapse).
`LEFT JOIN escalation e ... WHERE e.status <> 'RESOLVED'`. Where a note has no
escalation, `e.status` is NULL, and `NULL <> 'RESOLVED'` evaluates to NULL,
not TRUE — so that row is dropped. The LEFT JOIN behaves as an INNER JOIN.
*Verified:* of 5,506 notes in the quarter, only 147 unique notes have a
non-RESOLVED escalation — 2.7% coverage. Those 147 are not a random
sample; they are notes that already generated an escalation, i.e. an
already-failing subpopulation. The reported rate is upward-biased by
construction, independent of any other bug.

D8 — `sla_config` fan-out (296 rows from 147 notes).
Every product_line/priority pair has 2 effective-dated rows (target tightened
2026-05-15). The join carries no date predicate, so each of the 147 notes
joins twice — exactly accounting for 147 × 2 = 296 — and can be measured
against a target that was not in force on its submission date.

D9 — Escalation status has no place in this metric's definition.
Delivery SLA breach is `delivered_at − submitted_at > target`. Escalation
status is a downstream consequence of a breach, not part of measuring one.
The corrected query drops the join entirely.

---

## 4. Metric 3 — Genuinely open escalations

Query file: `src/queries/waterfall/metric3_escalations.sql`

Reported: 149 open · 49.5 min avg time to first response
True: 120 genuinely open (43 additionally stranded, reported separately)

### Variance waterfall

| # | Correction applied | Open count | Δ |
|---|---|---:|---:|
| 0 | Reported figure | 149 | — |
| 1 | Exclude PENDING_POST (never posted, not "open") | 106 | −43 |
| 2 | Drop the created-date window (open is a status, not a period) | 120 | +14 |

### Defects

D10 — PENDING_POST counted as open (−43).
`WHERE status <> 'RESOLVED'` includes PENDING_POST. All 43 such rows have
`slack_thread_ts IS NULL` and `first_response_at_utc IS NULL` — they were
never posted to Slack and nobody has responded. They are not open work; they
are stranded, and they are the Part 3 recovery population.

D11 — "Open" bounded by creation date (+14).
Q5 filters `created_at_utc BETWEEN ... Q2 window`. "Open" is a status, not a
period: an escalation raised before Q2 and still unresolved is more urgent,
not less. This bound excludes 6 pre-Q2 escalations still OPEN and 8 raised
after 30 June (the replica carries data to 2026-07-06) that are also still
OPEN. 106 (in-window) + 6 (before) + 8 (after) = 120.

D12 — Phantom denominator on time-to-first-response.
Reported as "149 open, avg 49.5 min". `AVG()` skips NULLs, so 49.5 min is the
average over the 106 rows that have a response — not over 149, and not over
the true 120. 14 of the 120 genuinely open escalations have no first response
at all; the reported figure implies better coverage than exists.

---

## 5. Metric 4 — Genuine volume anomalies

Query file: `src/queries/waterfall/volume_anomalies.sql`

Reported: 28 of 91 days flagged
True: 2 genuine anomalies, out of 65 weekdays in the quarter (56 with a complete 14-day trailing window)

### Variance waterfall

| # | Correction applied | Days flagged | Δ |
|---|---|---:|---:|
| 0 | Reported figure | 28 of 91 | — |
| 1 | Weekday-only, per the stated business rule | 2 | −26 |
| 2 | Dedup, exclude void, Chicago day, require a complete 14-day window | 2 of 56 evaluable | 0 |

### Defects

D13 — The stated rule was never implemented (−26).
The business rule is "flag any weekday more than 30% below the trailing
14-day average." No weekday predicate exists in the query.
*Verified:* of the 28 flagged days, 2 are weekdays and 26 are weekends
(93% false positive rate). Weekend volume is naturally lower — that is the
normal pattern, not an anomaly.

D14 — The trailing baseline is itself contaminated by weekends.
Because the 14-day trailing window includes weekends, the baseline is pulled
down by the same low-volume days the rule should be excluding, which also
raises the risk of missing a genuine weekday drop (the bar it must clear is
lower than it should be).

D15 — Partial windows treated as complete.
Early in the quarter, fewer than 14 prior days exist. Of 65 weekdays in Q2,
9 do not have a full trailing window and are not safely evaluable; the
provided query judges them anyway.

Operational read: an alert firing 28 times in 91 days (roughly twice a
week) trains operators to ignore it. The 2 genuine anomalies were
indistinguishable from the 26 false ones.

---

## 6. Answers to the two business questions

### Is Decision A justified? At what magnitude?

Yes, but not for the reason the memo gives, and the memo understates the gap.

True Q2 pass rate is 76.8% on 1,566 audited notes, not 79.9% on 1,705.
Against the 90% target that is a 13.2-point gap, not 10.1.

The cause matters more than the size. On 2026-05-15 the audit rubric moved to
v2, which raised the pass threshold from 0.85 to 0.90 and reweighted four of
seven dimensions. The ETL was never updated for either change: it still scores
v2 audits with v1 weights (234 audits, understated by 0.0216 on average) and
still judges them against the v1 threshold (143 audits marked PASS that the
v2 rubric fails). A material part of the "decline" is the bar moving, not
performance falling.

Fund the remediation, but scope it against the right diagnosis. Retraining
MDS staff for a threshold change teaches the wrong lesson. The first action is
fixing the scoring pipeline; the second is telling the floor the standard
changed mid-quarter, which as far as these numbers show nobody was told. An
extra QA headcount justified by a 10-point gap should be re-justified against
13.2 points and a known scoring defect.

### Is Decision B safe to execute?

No. Do not execute it as it stands. Three named individuals are misplaced.

Achebe, Noor (MD-201) sits in the bottom five and would receive a
documented coaching plan. MD-201's status is INACTIVE. The leaderboard applies
no status filter, so a person no longer active is about to have a performance
document placed in their file, with no opportunity to respond.

Petronella, Emeka (MD-218) ranks second and is a leading candidate for the
recognition award. MD-218 is also INACTIVE.

Domingo, Rafael is two people. MD-206 and MD-227 are both ACTIVE, hired a
year apart, and the leaderboard groups by `mds_name` — so their work is merged
into one row of 338 notes, roughly double every other MDS. Split correctly,
MD-227 scores 0.9261 (7th of 32) and MD-206 scores 0.9034, which places
him in the genuine bottom five. The merge conceals a top performer and
shields the one person on the list who most plausibly needs support.

The corrected leaderboard is in `src/queries/waterfall/mds_leaderboard.sql`;
the query proving the three cases above is in the same file.

---

## 7. What I did not check

- Escalation failure pattern. `attempt_count` and `last_api_error` on the
  43 stranded PENDING_POST rows have not been profiled. Part 3 needs this to
  characterise *why* they never posted before building the recovery rule.

- Encounter-level note reuse. 1,566 in-quarter notes map to fewer unique
  `encounter_id`s than `note_id`s. I have not determined whether a repeated
  `encounter_id` is a legitimate addendum (a second note against the same
  visit) or a data quality issue distinct from the re-ingestion duplicates
  already found.

- Auditor bias. `auditor_mds_id` on `note_audit` was not analysed. I do
  not know whether pass rate or composite score varies systematically by
  auditor — a rater who is consistently harsher or more lenient would bias
  the leaderboard and the pass rate independently of MDS performance.

- Rubric version assignment at the boundary. Each audit carries its own
  `rubric_version`, but I did not verify what determines it near
  2026-05-15 — whether it is set from the note's submission date, the audit's
  own `audited_at_utc`, or something else. If it is keyed to audit time rather
  than note time, a note submitted under v1 could be judged under v2 or vice
  versa, which would change which notes belong in the D4/D6 corrections.

- Void timing relative to audit. Some notes are both audited and later
  marked void; I excluded all void notes from the pass rate uniformly. I did
  not check whether an audit that predates the void event should still count
  — a policy question, not just a data question, and one I could not resolve
  from the schema alone.

- `template_id` and `source_channel` as quality covariates. Whether note
  template or intake channel correlates with composite score or SLA breach
  was out of scope for this pass; it may be relevant to the remediation
  program's design, since a template-driven quality gap would call for a
  template fix rather than MDS retraining.