# Tighten Self-Dogfooding Configuration

Status: done
Date: 2026-06-16
Severity: Low
Source: 2026-06-16 structured review

## Summary

Henitai runs on itself (`.henitai.yml` targets `lib/`, `reports/` holds real
artifacts), but the self-run config is lenient: it uses the light operator set
and disables two kill criteria. For a mutation-testing tool, the strength of its
own dogfooding is a quality signal.

## Problem

`.henitai.yml`:
- `operators: light` — runs the reduced operator set, not `full`, so the four
  Full-only operators (`MethodChainUnwrap`, `RegexMutator`, `UnaryOperator`,
  `UpdateOperator`) never exercise the tool's own suite.
- `coverage_criteria.timeout: false` and `process_abort: false` — two kill
  criteria disabled, reducing rigor of the self-run.

## Fix Plan

1. **Measure first.** Run henitai on itself with `operators: full` and both
   criteria enabled. Capture the new survivor set and runtime. This tells us
   whether `light` was chosen for speed or to hide survivors.
2. **Triage survivors.** For each new survivor under `full`, either kill it with
   a test (preferred — improves the suite) or record it as a known
   equivalent/accepted mutant with rationale.
3. **Flip the config** to `operators: full` and re-enable `timeout` /
   `process_abort` once the survivor backlog is addressed or explicitly
   accepted.
4. **Wire into CI.** Add (or confirm) a CI job that runs the full self-mutation
   pass and fails on regression below an agreed mutation-score threshold.
5. If full-run wall time is the blocker, pair this with the survivor-only rerun
   feature to keep the iterative loop fast while CI runs full.

## Acceptance

- `.henitai.yml` uses `operators: full` with `timeout` and `process_abort`
  enabled, OR each exception is documented with rationale.
- Self-run survivors triaged (killed or accepted-with-reason).
- CI enforces a mutation-score threshold.

## Related

- [[2026-06-16-review-test-overmocking-and-gaps]]
- [[2026-06-16-review-doc-debt]]
