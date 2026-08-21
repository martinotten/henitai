# `execution_engine_spec` Uses `send` to Reach Private Test Exclusion

Status: done (2026-08-21)
Date: 2026-08-21
Severity: Low
Source: discovered while seeding budgets for
`spec/infra/private_method_reach_spec.rb`; no ticket existed

## Summary

[`spec/henitai/execution_engine_spec.rb`](/Users/martinotten/projects/mo/henitai/spec/henitai/execution_engine_spec.rb)
reaches the private `reject_excluded_tests` 3 times.

## Problem

- Test exclusion decides which spec files a mutant is run against, so a wrong
  glob silently narrows every mutant's kill surface. It is worth a dedicated
  unit, not `send` reach through the engine.
- The rule that a `*` wildcard must not cross a directory boundary
  (`File::FNM_PATHNAME`) is the mutation-rich part and currently has no public
  seam.

## Fix Sketch

Extract `Henitai::ExcludedTestFilter` into
`lib/henitai/excluded_test_filter.rb`.

- Public `#initialize(patterns:)` and `#reject(tests) -> Array[String]`.
- Takes the pattern list, not the config object — the caller passes
  `Array(config.exclude_tests)`, keeping the filter free of configuration
  concerns.
- `ExecutionEngine#reject_excluded_tests` becomes a construction plus call at
  its existing call site, then is deleted.
- Top-level lib file, so `spec/infra/lib_spec_coverage_spec.rb:36-42` requires
  `spec/henitai/excluded_test_filter_spec.rb`. Do **not** add it to the
  `Steepfile` — `spec/infra/steep_scope_spec.rb` pins that list exactly.

## Test Plan

- Capture `bundle exec henitai run 'Henitai::ExecutionEngine#*'` MS/MSI before
  starting; host plus collaborator must not fall below it.
- Move the 3 existing examples into the new spec against the public method, and
  add directory-boundary cases for the `FNM_PATHNAME` rule.
- Lower this file's budget in `spec/infra/private_method_reach_spec.rb` in the
  same commit.

## Resolution (2026-08-21)

Extracted `Henitai::ExcludedTestFilter` (`lib/henitai/excluded_test_filter.rb`)
with `spec/henitai/excluded_test_filter_spec.rb`.

- Public `#initialize(patterns:)` and `#reject(tests)`. It takes the pattern
  list rather than a configuration object, so the path-matching rule is free
  of configuration lookup and directly testable; `ExecutionEngine` reads
  `config.test_excludes` defensively and passes it in.
- The `FNM_PATHNAME` rule now has explicit coverage on both sides: a single
  `*` must not cross a directory separator, and a pattern that spans
  directories explicitly still matches. Without `FNM_PATHNAME` an exclude as
  narrow as `spec/a/*_spec.rb` would swallow every test below `spec/a`.
- Relative-versus-absolute matching is covered too, since both sides are
  expanded before comparison.
- `nil` patterns are accepted alongside `[]`, matching what the engine can
  actually hand over.

Not added to the `Steepfile`: `spec/infra/steep_scope_spec.rb` pins that list.
Budget removed from the private-reach ratchet in the same commit.
