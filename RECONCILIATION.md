# Reconciliation — Q2 FY26 Ambient Ops Review

## Metric 1: Notes audited & audit pass rate

**Reported:** 1,705 notes · 79.9% pass · 0.9055 avg composite  
**True:** 1,566 notes · 76.8% pass · 0.9161 avg composite

### Variance waterfall
| # | Correction applied | Notes | Pass rate | Δ notes | Δ pass rate |
|---|---|---:|---:|---:|---:|
| 0 | Reported figure | 1,705 | 79.9% | — | — |
| 1 | Exclude void notes (`is_void = true`) | 1,687 | 79.9% | −18 | 0.0 |
| 2 | Clinician SCD fan-out fix (current record only) | 1,562 | 79.8% | −125 | −0.1 |
| 3 | Deduplicate `note` to latest ingestion per `note_id` | 1,546 | 79.7% | −16 | −0.1 |
| 4 | Evaluate pass/fail against the **effective rubric threshold** | 1,546 | 71.6% | 0 | **−8.1** |
| 5 | Define the quarter on the America/Chicago business day | 1,566 | 71.4% | +20 | −0.2 |
| 6 | Recompute composite from the **effective rubric weights** | **1,566** | **76.8%** | 0 | **+5.4** |

### Findings
- D1: void notes not excluded (18 notes)
- D2: clinician SCD fan-out — 4 clinicians with 2 rows, no effective-date predicate (125 notes double-counted)
- D3: note re-ingestion duplicates — 62 note_ids with 2 rows (16 in-quarter)
- D4: ETL applied v1 threshold (0.85) to v2 audits (0.90) — 143 audits wrongly PASS
- D5: quarter bound excluded 2026-06-30 entirely; UTC vs America/Chicago boundary
- D6: ETL computed v2 composites with v1 weights — 234 audits, avg understated by 0.0216

### ⚠️ Opposite-direction corrections
D4 moves pass rate −8.1; D6 moves it +5.4. Fixing only D4 lands at 71.6% —
further from truth (76.8%) than the original 79.9%.

## Metric 2: Delivery SLA breach rate
_TBD_