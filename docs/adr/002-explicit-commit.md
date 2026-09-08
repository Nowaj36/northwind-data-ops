# ADR 002 — Commit is an explicit action, never a row-click

## Status

Accepted

## Context

The Ops Director asked for a decision to be committed by clicking the row:
*"one click, straight from the table. I don't want to hunt for a Save button."*
The QA Lead asked for the opposite: *"anything that changes a clinician-facing
record needs a deliberate second confirmation. We've had accidental
dispositions before and it created a real mess with a physician group."*

The build's own hard requirement R7 sides with QA: *"The commit is explicit and
optimistic: UI reflects the change immediately, rolls back visibly on failure.
Row-click alone must not mutate anything."*

The queue holds 402 failed audits today and is specified to hold 3,000 on a
Monday morning. A `triage_decision` row is not a display artefact — it drives
retraining, coaching plans, and QA escalation, and it names an MDS.

## Options considered

**A. Row-click commits.** What the Ops Director asked for. Fastest possible
loop: one interaction per case. But a mis-click is indistinguishable from a
decision, and on a queue this size mis-clicks are not hypothetical. It also
makes the disposition and reason-code fields meaningless — there is nowhere to
set them before the commit fires.

**B. Row-click selects; a button commits.** Two-stage. Selection is free and
reversible; commit is deliberate. Costs the operator one interaction per case
against option A.

**C. Row-click commits, with an undo window.** A middle path: commit
immediately, offer a five-second undo toast. Preserves the one-click loop and
makes mistakes recoverable. Rejected because undo must survive the operator
moving on — if they mis-click and immediately click the next case, the toast is
gone and the wrong decision stands. It also needs the reversibility the schema
does not yet have (see DECISIONS.md, Conflict 4).

## Decision

**B.** Row-click selects and populates the provenance panel. Committing
requires the disposition dropdown, the reason-code dropdown, and an explicit
button press.

The deciding argument is asymmetry, not principle. A wasted click costs a
second. A wrong disposition on a clinician-facing record costs an afternoon of
unwinding and some credibility with a physician group — the QA Lead has
already paid that bill once. When one side of a trade is bounded and small and
the other is unbounded, the bounded cost wins.

Both commit buttons are gated: single commit requires exactly one selected row
and both dropdowns set; bulk commit requires two or more. They are mutually
exclusive on selection count, so the operator never chooses between them — the
selection decides which is live.

## Consequences

- **The core loop is 3 interactions after selection** (disposition, reason,
  commit) — one under R2's budget of 4. The spare interaction is what pays for
  commit staying explicit.
- **The Ops Director's primary request is not met.** They work this queue daily
  and I made their loop slower than they asked. This is the single most likely
  thing to be argued about on delivery, and the argument is legitimate.
- **Optimistic feedback is carried by the button, not the row.** The commit
  button's `loading` binds to `commitDisposition.isFetching`, so the in-flight
  state is visible immediately; success and failure notifications are both
  enabled on the query.
- **On failure, the form is not cleared.** The pending decision survives for
  retry rather than silently vanishing. This turned out to matter: an earlier
  version cleared the dropdowns from the *button's* click handler alongside the
  query trigger. Retool fires click handlers together rather than in sequence,
  and the query is asynchronous — so the fields cleared mid-flight and the
  insert wrote NULLs. The not-null constraint caught it; a nullable column would
  have written silent garbage. The fix was moving the clear actions into the
  query's own success handler, where they cannot run before the insert returns.
- **Bulk commit is safe to double-submit** via `ON CONFLICT (note_id) DO
  NOTHING` against a unique index. That same index currently blocks
  corrections, which is a real problem recorded in DECISIONS.md Conflict 4.
- **Keyboard operation would have recovered most of the lost speed** and is not
  implemented; see UX_RATIONALE.md §4. Had it worked, the gap between what the
  Ops Director asked for and what shipped would be much narrower.