# ADR 001 — Define the reporting quarter on the America/Chicago business day

## Status
Accepted

## Context

Every timestamp column in the replica is a naive `timestamp` in UTC. Ops runs
on the America/Chicago business day. The provided queries bound the quarter as
`submitted_at_utc BETWEEN TIMESTAMP '2026-04-01' AND TIMESTAMP '2026-06-30'`,
which is a UTC window ending at midnight — it excludes all of 30 June (83
non-void notes) and shifts every day boundary by 5 hours against the day the
business actually works.

## Options considered

**A. Leave the window in UTC.** Matches the stored data literally. Requires no
conversion, and is what the departed analyst did. But every daily figure is
cut 5 hours from the operational day, so a note submitted at 19:30 Chicago
lands on the following report day.

**B. Convert to America/Chicago at query time.**
`(submitted_at_utc AT TIME ZONE 'UTC' AT TIME ZONE 'America/Chicago')::date`.
Aligns reporting with the business day. Costs a per-row conversion, which is
unindexable as written.

**C. Add a materialised `submitted_business_date` column, populated by ETL.**
Cheapest to query and indexable, but requires a pipeline change I do not own
and cannot make within this assessment.

## Decision

**B**, with C noted as the production path.

The purpose of these numbers is to tell operators what happened on their day.
A quarter boundary that disagrees with the working day produces figures nobody
in Ops can reconcile against what they saw. Correctness of the boundary
outranks query cost at this data volume (6,235 notes).

DST is handled by the timezone database rather than a fixed offset — Chicago
is UTC−6 in Q1 and UTC−5 across all of Q2 FY26, so a hardcoded offset would be
correct here by accident and wrong in a quarter that spans a transition.

## Consequences

- Against the UTC window the quarter gains a net 20 audited notes: 21 enter
  (submitted late on a Chicago day that the UTC bound cut off, chiefly
  30 June) and 1 leaves (a note submitted just after UTC midnight on 1 April
  that belongs to the Chicago day of 31 March). 1,545 are unaffected.
- Every downstream metric must use the same predicate, or figures will not
  tie. Centralised as a single expression and unit-tested at the boundary
  (`tests/businessDayBoundary.test.ts`).
- Queries cannot use a plain index on `submitted_at_utc` for the date filter.
  At this volume it does not matter; at production volume the fix is C, or an
  expression index on the converted date.
- The same conversion is applied to the Part 2 queue and the Part 3 workflow,
  so the app and the report agree.