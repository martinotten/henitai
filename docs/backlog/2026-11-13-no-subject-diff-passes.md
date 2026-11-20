# A Diff Without Mutable Code Must Not Fail the Run

Status: proposed
Date: 2026-11-13
Severity: Low (false red in CI; advisory gate today)
Source: release PRs. PR #27 (release 0.4.0: `version.rb`, CHANGELOG,
lockfiles) failed "Mutation Testing (incremental)"; PR #41 (0.5.0) passed
only because it also carried feature code.

## Summary

`henitai run --since origin/main` on a diff whose changed Ruby files
contain no subjects (e.g. only `VERSION = "0.4.0"`) aborts with
`Henitai::CoverageError: Coverage data is unavailable for the configured
source files` and exits `2` (framework error). Nothing was there to mutate,
so the run should pass with an explicit "nothing to mutate" message.

## Analysis

- Coverage is Gate 0 and runs before subject resolution
  (`CoverageBootstrapper`, AGENTS.md "Coverage is a required gate before
  subject resolution"). A file whose only code runs at require time —
  before coverage starts — has no usable coverage, so the gate raises.
- AGENTS.md already defines the intended semantics: "A run with no
  scoreable mutant passes its threshold only when there was nothing to
  score." The CoverageError path pre-empts that rule.
- `excludes` exists in the configuration now, so excluding `version.rb`
  would work around it, but every adopter's release PR hits the same
  case; the fix belongs in henitai.
- Not re-verified on 0.6.0 (the 0.6.0 release was committed directly to
  `main`, without a PR run). Reproduce first.

## Requirements

1. Reproduce: a diff touching only a constant-only file under `includes`
   → today exit 2.
2. Files that yield no subjects do not need coverage: the coverage gate
   only considers source files that contain at least one subject (or:
   resolve subjects of the diff before deciding whether coverage is
   needed — keeping Gate 0 before generation for files that do).
3. A run with no subjects at all exits `0` with a clear message
   ("no mutable code in the selected files") and still writes a valid,
   empty-but-scoped report.
4. Missing coverage for files that *do* contain subjects stays a
   `CoverageError` — this item must not weaken the gate.

## Acceptance criteria

- Version-only diff: exit 0, message, no CoverageError.
- Diff with an uncovered method: still `CoverageError` (unchanged).
- Release PRs of this repository pass the mutation job.

## Related

- `lib/henitai/coverage_bootstrapper.rb`, `lib/henitai/runner.rb`
- `.github/workflows/ci.yml` (`mutation` job)
