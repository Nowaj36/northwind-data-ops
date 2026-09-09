# DECISIONS — Stakeholder conflicts in the Triage Workbench

Six requests arrived over two weeks in three channels. They cannot all be
satisfied — two pairs are in direct opposition, one asks for data the replica
does not contain, and one is in tension with a constraint I introduced myself
while solving a different problem.

Below: each conflict, who I would go back to and what I would ask them, what I
chose, and what I gave up.

---

## Conflict 1 — Row-click commits (R-01) vs. deliberate second confirmation (R-02)

**The conflict.** The Ops Director wants a decision committed by clicking the
row: *"one click, straight from the table. I don't want to hunt for a Save
button."* The QA Lead wants the opposite: *"anything that changes a
clinician-facing record needs a deliberate second confirmation. We've had
accidental dispositions before."*

This is not a matter of degree. One says the click *is* the commit; the other
says a click must never be the commit. No design does both.

**Who I would go back to, and what I would ask.** The Ops Director — and the
question is not "which do you want," it is: *"QA says you've had accidental
dispositions reach a physician group. How many, and what did it cost to unwind?
If it happened once and took an afternoon, I'll build it your way. If it has
happened repeatedly, the second click is cheaper than the cleanup."* The Ops
Director is optimising for speed on a queue they work daily; the QA Lead is
optimising against an incident they have already lived through. Only one of
them has the incident count, and it decides this.

**What I chose.** The QA Lead's position. Row-click selects and nothing more;
committing is an explicit button press. Bulk commit adds a confirmation modal
naming the disposition, the reason, and the row count.

**Why.** Three reasons, in order. The failure is asymmetric — a wasted click
costs a second, a wrong disposition on a clinician-facing record costs an
afternoon and some trust. The Ops Director's request also has a selection
problem inside it: a click that commits means a *mis*-click commits, and on a
3,000-row queue (R-03) mis-clicks are certain. And this is a hard requirement of
the build (R7: *"Row-click alone must not mutate anything"*), so the QA Lead and
the spec agree.

**What I gave up.** The Ops Director's single biggest stated want, and it is a
real loss — they work this queue and I have made their loop slower than they
asked. I bought some of it back by holding the loop to **3 interactions after
selection**, and by making single and bulk commit mutually exclusive on
selection count so the operator never has to choose between buttons. That is
mitigation, not agreement.

---

## Conflict 2 — Whole queue on one screen, no scrolling (R-01) vs. 3,000 cases (R-03)

**The conflict.** *"See the whole queue on one screen. No scrolling, no
pagination, no 'next 50'"* against *"Monday morning queues run 2,500–3,000
cases."* At 1366×768 a dense row is ~33px and the viewport holds roughly 18 of
them. 3,000 rows is not a layout problem, it is arithmetic.

**Who I would go back to, and what I would ask.** The Ops Director — and I would
ask what *"know where we stand"* actually means, because I think that is the
real request and whole-queue-visible is a proposed solution to it. *"When you
say you want to look at it and know where we stand — what are you checking?
Total count? How much is urgent? Whether it's growing week over week? I can give
you that in a header line that stays true at 3,000 cases. No screen can show you
3,000 rows."*

**What I chose.** Internal scroll on the table, no pagination, full result set
loaded — so it is one continuous queue rather than "next 50", which is the part
of the request I read as load-bearing. The footer carries the count
("1 of 402 selected").

**What I gave up.** Literal no-scrolling. And I did not build the standing
header of queue-health numbers that I just argued is the real request — that is
the honest next step here, not something I shipped.

---

## Conflict 3 — Full note text and seven sub-scores (R-02) vs. one screen (R-06, R-01)

**The conflict as it appeared.** The QA Lead wants the full note text *and* all
seven sub-scores visible simultaneously, nothing behind a click. The Head of
Product wants one screen and explicitly not a five-tab application. The Ops
Director wants the queue on that same screen. Note text is hundreds of words;
seven sub-scores is seven labelled values; the queue is the queue.

**What I found when I went to build it.** The operational replica **does not
contain note text.** `note` carries `word_count` but no content column —
`note_id`, `ingestion_id`, `encounter_id`, `clinician_id`, `mds_id`,
`product_line`, `priority`, `template_id`, `source_channel`, `word_count`, three
timestamps, `is_void`, `void_reason`. That is the whole table. The QA Lead is
asking for a field that does not exist in the data I was given.

That changed the shape of the conflict rather than resolving it in my favour.
Note text was the part that could not share a screen with the queue; seven
sub-scores fit in three lines. Once the text turned out to be unavailable, most
of the R-02/R-06 tension went with it — not because I made a good call, but
because a data constraint made the call for me. Worth saying plainly.

**Who I would go back to, and what I would ask.**

To the **QA Lead**: *"The replica has no note text — only word count. Is the
text available from another system, and if so what does it cost to fetch per
note? If it's a second per call, that changes the design. If it isn't available
at all, we need to talk about what a defensible call looks like without it,
because right now reviewers are working from scores alone."* This is a
data-availability question, not a design one, and it blocks their requirement
entirely.

To the **Head of Product**, only if the answer above is "yes, it's available":
*"Note text cannot share this screen with the queue at 1366×768. Is a detail
drawer over the queue still 'one screen' to you, or does it count as the second
tab you don't want?"*

**What I chose and shipped.** The provenance panel now carries **all seven
sub-scores** — accuracy, completeness, formatting, terminology, HPI, ROS, plan —
alongside the composite, the threshold that applied to that note, the rubric
version, and delivery against the SLA in force on the note's own date. Three
lines, always visible for the selected case, no drill-down.

This matters more than it sounds. A composite of 0.8813 against a 0.9 threshold
tells a reviewer the note failed; it does not tell them *what* failed. The
sub-scores do, and that is exactly the QA Lead's stated worry — reviewers
guessing from an incomplete view. Their example was a truncated note preview,
but a lone composite has the same defect.

**What I gave up.** Note text, which I could not have supplied. And one honest
caveat on "nothing hidden behind a click": the panel renders for the *selected*
row, so a reviewer does click a case before seeing its sub-scores. I read that
as selection rather than a drill-down — you cannot triage a case you have not
picked — but the QA Lead may read it differently, and if they do, the fix is a
column group in the table rather than an argument.

---

## Conflict 4 — Reversible state changes (R-04) vs. the idempotency guard I built

**The conflict.** Compliance requires that every state change be *"attributable
to a named user, timestamped, and reversible."* To make bulk commit safe to
double-submit (R8), I added a unique index on `triage_decision(note_id)` — one
decision row per note, ever — so `ON CONFLICT DO NOTHING` turns a repeat submit
into a silent no-op.

That same constraint means a disposition **cannot be corrected**. A second,
later decision for the same note is rejected by the index. I satisfied
idempotency by making the table append-once, and in doing so I broke
reversibility.

Nobody stated these two requirements in the same breath, which is exactly why it
slipped: the constraint arrived while I was solving a different problem, and I
only saw the collision when I read Compliance's request against my own DDL.

**Who I would go back to, and what I would ask.** Compliance: *"Does
'reversible' mean the original decision must remain visible in the audit trail
alongside the correction, or may it be overwritten? The first needs a versioned
table, the second needs an update path. Different schemas, and I would rather
build the right one once."*

**What I chose.** Attribution and timestamping are met — `decided_by` comes from
`current_user.email` (Retool's authenticated session, not operator input, so it
cannot be spoofed by the person being audited against it), and `decided_at_utc`
defaults to `now()`. **Reversibility is not met.**

**What I would build.** Drop the unique index on `note_id`. Add
`superseded_at_utc timestamp NULL` and enforce one *live* decision per note:

```sql
CREATE UNIQUE INDEX idx_triage_decision_live
  ON triage_decision (note_id)
  WHERE superseded_at_utc IS NULL;
```

A correction stamps `superseded_at_utc` on the old row and inserts a new one.
Idempotency survives — a repeat submit still conflicts against the live row —
and history is preserved rather than blocked. This is the same partial-index
pattern I used for `escalation_repost_audit` in Part 3, where a unique index on
`(escalation_id) WHERE outcome = 'SUCCESS'` is what makes the recovery workflow
idempotent. I had the pattern in hand and did not apply it here.

**What I gave up.** Nothing I would defend. This is a schema bug, found by
reading a stakeholder requirement against my own DDL, and the fix above is
about twenty minutes I did not have left inside the budget. I would not ship
this to Compliance as-is.

---

## Conflict 5 — Keyboard-first operation (R-05) vs. what the platform allowed

**The request.** *"The leads are fast and they hate the mouse... hands on the
keyboard and blow through the queue — that'd be the single biggest win."*

This does not conflict with another stakeholder. It conflicts with Retool.
Custom shortcuts are configurable only at app scope; every component here is
page-scoped, and app-scope handlers cannot reference page-scoped components.
Every route I tried — direct reference, namespaced reference, indirection
through a page-scoped JS query, moving the query itself to page scope — hit the
same boundary. Details and the proposed workaround are in `UX_RATIONALE.md` §4.

**Who I would go back to, and what I would ask.** The Ops Director, with the
honest version: *"This is the one I couldn't deliver, and it's the one you
called your biggest win. I have an approach that should work — a focus-holding
key capture inside the page scope — but I haven't proven it. Is it worth a day
to build and test properly, or would you rather I spend that day elsewhere?"*
That is their call, not mine.

**What I gave up.** The Ops Director's stated single biggest win, on top of
overruling their first request in Conflict 1. If I were presenting this in
person I would lead with that — two of their three asks did not survive, and
they should hear the reasoning from me rather than discover it in the app.

---

## Summary

| Conflict | Chose | Gave up |
|---|---|---|
| Row-click commit vs. second confirmation | QA Lead — explicit commit, confirmation on bulk | Ops Director's one-click loop |
| Whole queue visible vs. 3,000 rows | Internal scroll, no pagination, full set loaded | Literal no-scrolling; queue-health header not built |
| Note text + sub-scores vs. one screen | All seven sub-scores in the provenance panel | Note text — not present in the replica |
| Reversibility vs. idempotency | Idempotency | **Reversibility — a schema bug, fix specified above** |
| Keyboard-first vs. platform scope | Mouse loop at 3 interactions | R-05 entirely |

Four of these are trades I would stand behind and expect to argue for. The
reversibility gap is not — it is a bug I introduced, and it is the first thing I
would fix before calling this shippable.