# Untested Factory Error Paths and Tautological Mock Specs

Status: backlog
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
   happy-path const lookup.
2. **Integration factory:** add the analogous failure-path spec
   (`Henitai::Integration.for("nope")` → `ArgumentError`).
3. **De-tautologize `per_test_coverage_selector_spec`:** drive it with a real
   `CoverageReportReader` over a small fixture (temp JSON) so the spec fails if
   the selector stops consulting the reader.
4. **Fix the concurrency spec:** replace `sleep`-based fake sync with the
   real-process barrier pattern already used in
   `process_worker_runner_spec.rb`, or drop the sleep and assert on a
   deterministic observable. Keep the fake-runtime test only for edge cases
   (timeout/signal), labeled as such.
5. Run full suite; confirm new specs fail before the (already-correct) code is
   in place by temporarily breaking the branch, then restore.

## Acceptance

- Both factory `ArgumentError` paths have passing specs.
- `per_test_coverage_selector` spec exercises a real reader and fails if the
  reader is bypassed.
- No `sleep`-as-synchronization remains in `execution_engine_spec.rb`.

## Related

- [[2026-06-16-review-test-overmocking-and-gaps]]
- [[2026-06-16-review-flaky-timing-specs]]
