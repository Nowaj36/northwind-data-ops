# Submission Checklist

Fill this in, commit it, and confirm every line before you submit. An unfilled
checklist is treated as an incomplete submission.

Candidate: Nowaj Chowdhury  Date submitted: 2026-09-09  Hours spent (honest): ~10

Legend: `[x]` done · `[~]` partially done, explained · `[ ]` not done, explained

---

## Access

- [x] Retool app shared with moontasir.abeer@commure.com
- [x] Retool app shared with musfiqur.preo@commure.com
- [x] Retool app shared with shakira.mustahid@commure.com _(named in the brief, not on this checklist)_
- [x] A Retool Release version is tagged — workflow at 3.0.1
- [x] GitHub repo accessible to both reviewers — URL: https://github.com/nowaj36/northwind-data-ops
- [ ] Video link (≤12 min, single take, screen + voice): __________

Workflow sharing is blocked. Retool's free tier does not expose access
controls on workflows — "Access controls isn't available on your plan." The app
above is shared with all three reviewers. The workflow (Stranded Escalation
Recovery, release 3.0.1) is built and released in my workspace but cannot be
shared the same way. Its four SQL blocks are in the repo at
`src/queries/part3/`, it runs end to end in the video, and I can screen-share
the canvas in the live review.

---

## Part 1 — Reconciliation

- [x] RECONCILIATION.md committed
- [x] Data profiling written up — grain and actual key uniqueness for all seven tables
- [x] Variance waterfall with per-correction quantification, for each headline metric
- [x] "The quarter" defined and defended — America/Chicago business day; ADR 001
- [x] Decision A and Decision B answered in ≤400 words
- [x] Known unknowns stated

Number of defects I believe I found: 18 (D1–D18)

Six on the audit pass rate, three on SLA breach, three on open escalations,
three on volume anomalies, three on the MDS leaderboard. Two of them (D4 and D6)
move the pass rate in opposite directions, so a partial fix lands further from
the truth than the original query — called out explicitly in RECONCILIATION.md §2.

---

## Part 2 — Triage Workbench

- [x] Works at 1366×768, no vertical scroll on the primary pane (R1)
- [x] Interaction count per case: 3 after selection (R2, math in UX_RATIONALE.md §2)
- [ ] Keyboard-only core loop, keymap documented (R3)
- [~] Selection / scroll / filters survive a refresh (R4)
- [x] Provenance panel shows the SLA target in force on the note's date (R5)
- [x] Empty, loading and error states designed; error state demoed in video (R6)
- [x] Explicit commit, optimistic, with visible rollback (R7)
- [x] Bulk action, safe to double-submit (R8)
- [~] Status survives greyscale; contrast ≥4.5:1 (R9)
- [x] Queue derived from my corrected logic (R10)
- [x] UX_RATIONALE.md committed, including two rejected layouts and the requirement I did not fully satisfy

R3 — not met. This is the requirement I deliberately did not satisfy.
Retool exposes custom shortcuts only at app scope; every component here is
page-scoped, and app-scope handlers cannot reference them. Four routes tried,
all blocked by the same boundary. Full account and the untested approach I would
try next: UX_RATIONALE.md §4.

R4 — partial. Selection survives refresh (persist-row-selection, plus a
full result set with no pagination). Filter state does not — it resets on
refresh, and binding it to a state variable is work I did not reach. Scroll
follows selection in practice but I have not verified it independently.

R9 — partial. Colour-independence holds by construction: every status
carries its own text (`URGENT`/`STANDARD`, `AMBIENT LIVE`/`AMBIENT ASSIST`,
`PASS`/`BREACH`), and the provenance panel states the numeric gap from threshold
rather than signalling severity by colour. The ≥4.5:1 ratio on Retool's default
tag colours is not measured — the light-pink `STANDARD` and light-blue
`AMBIENT LIVE` badges are the ones I would check first.

---

## Part 3 — Recovery workflow

- [x] Detection rule defined and justified, no hardcoded IDs (W1)
- [x] Posts to a real endpoint I control (W2) — webhook.site; the URL is visible in the video
- [x] Idempotent across repeat runs, demonstrated in video (W3)
- [~] Rate limit ≤1 rps with jitter; exponential backoff on 429/5xx (W4)
- [ ] Dead-letter path after N attempts, N justified (W5)
- [x] Safe to run concurrently; guard explained (W6)
- [x] Audit trail table designed by me; DDL in repo, keys/types/indexes justified (W7)
- [x] Reconciliation query proving zero stranded, zero duplicates (W8)

W3 evidence: 43 stranded → 43 posted → 43 audit rows → 0 duplicate audit
rows → 0 remaining stranded. In the reconciliation query, `successful_reposts`
and `distinct_escalations` both read 43 — if any record had posted twice they
would differ.

W6 guard: claim-then-process. The detection block does not `SELECT`; it
`UPDATE`s and returns, combining `FOR UPDATE SKIP LOCKED` (protects the instant
between select and update), a `PENDING_POST → POSTING → POSTED` transition
(protects after the lock releases), and `NOT EXISTS` against a SUCCESS audit row
(protects across runs). Underneath, a partial unique index on
`(escalation_id) WHERE outcome = 'SUCCESS'` makes more than one success per
escalation structurally impossible. ADR 003.

W4 — partial. Sequential loop with a fixed 1000ms iteration delay, so the
≤1 rps budget holds. No jitter, no backoff on 429/5xx. Specified in README with
the reasoning for why jitter matters here in particular — the outage being
recovered from hit 43 records in two tight windows, and identical retry timing
reproduces the herd that caused it.

W5 — not done. A record that fails today stays `PENDING_POST` with no audit
row, so the next run retries it — safe, but it can loop indefinitely without
anyone noticing, which is the same silent-failure shape as the original bug.
N=3 and the design are specified in the README.

---

## Part 4 — Practice

- [x] Commits span ≥2 calendar days
- [x] ≥1 PR with my own review comments
- [~] JS lives in the repo as versioned modules, imported into Retool
- [ ] Tests green in GitHub Actions — covering TZ boundary, dedupe, effective-dated lookup, idempotency key
- [x] ≤3 ADRs in docs/adr/ — three: quarter definition, explicit commit, claim-then-process
- [x] DECISIONS.md — stakeholder conflicts identified and resolved (five of them)
- [x] AI_USAGE.md — including instances where I overrode AI output
- [x] README answers "what is wrong with this assessment?" (≤150 words)

Code out of the canvas — partial. All SQL — the queue query, every waterfall
query, the workflow blocks, and the DDL — lives in `src/` and is what runs in
Retool. Very little JavaScript exists to extract: the workflow uses REST API
blocks rather than JS loop runners, because Retool Workflows' JS sandbox has no
`fetch` (confirmed by `ReferenceError: fetch is not defined` on every
iteration), so the one JS block that remains is a three-line run-context
generator. That is committed, but calling it a "versioned module" would be
generous.

Tests — not done. Cut for time, and the honest cost is that four boundary
behaviours are asserted only by the queries themselves, not by anything that
would catch a regression. The four cases and their edges are specified in the
README; each is a pure function that would be straightforward to test.

---

## Declaration

- [x] Every number in my written deliverables is reproducible from a query in this repo.
- [x] AI_USAGE.md is complete and accurate.
- [x] This is my own work and I can explain and modify any part of it live.