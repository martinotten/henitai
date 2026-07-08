# Untested Factory Error Paths and Tautological Mock Specs

Status: done
Date: 2026-06-23
Severity: Medium
Source: 2026-06-23 structured review

## Summary

Two factory error paths raise `ArgumentError` on unknown names but have no
spec, and several specs are tautological — they assert on injected mock return
values and would pass even if the code under test ignored its inputs. Extends
the earlier [[2026-06-16-review-test-overmocking-and-gaps]] work.

## Problem

### Untested error paths
- `Reporter.reporter_class(name)` raises `ArgumentError, "Unknown reporter:..."`
  on a bad name — no spec asserts this. There is no `reporter_spec.rb`.
- `Integration.for(name)` raises `ArgumentError, "Unknown integration:..."` —
  no spec covers the failure branch.

### Tautological / weak specs
- `spec/henitai/per_test_coverage_selector_spec.rb` stubs the injected
  `CoverageReportReader` entirely; the spec would still pass if `filter`
  ignored the reader and returned a hard-coded value. No coupling between test
  and real behavior.
- `spec/henitai/execution_engine_spec.rb` uses `sleep 0.001` as a fake
  synchronization point with fully-mocked integration — the sleep does not
  interact with the mock, so it proves nothing about concurrency and is a
  potential CI flake.

## Fix Plan

1. **Reporter factory (red→green):** add `spec/henitai/reporter_spec.rb`.
   `expect { Henitai::Reporter.reporter_class("nope") }
   .to raise_error(ArgumentError, /Unknown reporter/)`. Also cover the
   happy-path const lookup. — done: new `spec/henitai/reporter_spec.rb`
   covers `.reporter_class` (happy path for all 4 built-ins + the
   `ArgumentError` branch) and `.run_all` (delegates to the resolved class
   with shared config/history_store, and propagates the factory's
   `ArgumentError`). Removed `reporter.rb` from the `lib_spec_coverage_spec.rb`
   allowlist now that it has a direct spec.
2. **Integration factory:** add the analogous failure-path spec
   (`Henitai::Integration.for("nope")` → `ArgumentError`). — already done by
   prior work: `spec/henitai/integration/rspec_spec.rb:626` covers this
   exact case. Stale item; no action needed.
3. **De-tautologize `per_test_coverage_selector_spec`:** drive it with a real
   `CoverageReportReader` over a small fixture (temp JSON) so the spec fails if
   the selector stops consulting the reader. — done: added two examples using
   a real `CoverageReportReader` (default, uninjected) over a `Dir.mktmpdir`
   fixture — one with a per-test report present (asserts the real
   file→reader→selector pipeline narrows correctly), one with the report
   file absent (asserts the graceful fallback to all candidates). Kept the
   original mocked example too — it still usefully pins the exact
   filtering/mapping logic in isolation. Verified via red-check: stubbing
   `filter` to a no-op `Array(tests)` broke all three (new real-reader spec,
   the original mocked spec, and an existing `execution_engine_spec.rb`
   integration example) — confirmed real coupling, then restored.
4. **Fix the concurrency spec:** replace `sleep`-based fake sync with the
   real-process barrier pattern already used in
   `process_worker_runner_spec.rb`, or drop the sleep and assert on a
   deterministic observable. Keep the fake-runtime test only for edge cases
   (timeout/signal), labeled as such. — done, simpler than proposed: the two
   `sleep 0.001` calls in `execution_engine_spec.rb` ("keeps jobs=1 on the
   linear execution path" / "runs linearly when jobs are not configured")
   were pure vestige — the assertion (`thread_ids.uniq.size == 1`) is a
   property of linear execution regardless of timing, so the sleep
   synchronized nothing and a barrier pattern would have been solving a
   problem that didn't exist. Removed both; no behavior or coverage lost.
5. Run full suite; confirm new specs fail before the (already-correct) code is
   in place by temporarily breaking the branch, then restore. — done for
   both the selector (item 3) and the reporter factory (temporarily removed
   the `rescue NameError` re-raise in `reporter_class`, confirmed both new
   `ArgumentError` examples fail with the raw `NameError` instead, restored).

**Bonus finding while closing item 4:** re-verified
`[[2026-06-16-review-flaky-timing-specs]]` (status: partial) and found it is
now also fully resolved — `parallel_execution_runner_spec.rb` (the other
`sleep`-based file it named) was deleted entirely in
`[[2026-06-23-review-dead-parallel-runner]]`; `process_worker_runner_spec.rb`
has no live `sleep` calls (only comments describing past removal); and
`cli_spec.rb` has no live `Dir.chdir` calls (only a comment explaining why
one isn't needed). Flipped to `done` in its file and the 2026-06-16 index.

## Acceptance

- Both factory `ArgumentError` paths have passing specs. — met.
- `per_test_coverage_selector` spec exercises a real reader and fails if the
  reader is bypassed. — met.
- No `sleep`-as-synchronization remains in `execution_engine_spec.rb`. — met.

## Related

- [[2026-06-16-review-test-overmocking-and-gaps]]
- [[2026-06-16-review-flaky-timing-specs]]
