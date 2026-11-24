# Baseline Suite Has a Fixed 300 s Timeout, Reported as a Failure

Status: done (2026-11-24)
Date: 2026-11-24
Severity: High for large projects (henitai cannot start), Low here (flaky CI)
Source: PR #57 CI, mutation job failed twice, passed on the third run

## Observation

The coverage bootstrap runs the configured suite through
`Integration#run_suite(test_files, timeout: DEFAULT_SUITE_TIMEOUT)`
(`lib/henitai/integration.rb`, `DEFAULT_SUITE_TIMEOUT = 300.0`). In CI the
dogfood baseline (2671 examples under coverage) takes close to that limit:
the passing run's whole henitai step took 4.5 minutes, and both failed runs
ended at exactly 5:02 with

```text
Configured test suite failed while generating coverage (see reports/mutation-logs/baseline.log)
(Henitai::CoverageError)
```

Locally the same command and a fresh checkout pass well under the limit.

## Problems

1. A project whose suite takes more than 5 minutes under coverage can never
   run henitai: the limit is not configurable.
2. `BootstrapErrorMessage` says "failed" for a timeout. The suite did not
   fail; it was stopped. Users (and we, in PR #57) look for a failing test
   that does not exist.

## Fix Sketch

- Message: when the suite result is a timeout, say so and name the limit,
  e.g. "Configured test suite did not finish within 300 s while generating
  coverage".
- Limit: make it configurable (e.g. `coverage.suite_timeout`), or derive it
  from the measured suite time of a previous baseline, with a generous
  default.
- CI: the mutation job already prints the baseline log tail on failure
  (`.github/workflows/ci.yml`, since PR #57).

## Test Plan

- `BootstrapErrorMessage` spec: a timeout result yields the timeout message.
- `CoverageBootstrapper` spec: the configured limit reaches `run_suite`.
- Configuration and schema specs for the new option, if one is added.

## Resolution

- `mutation.suite_timeout` (positive seconds, default 900) limits each
  baseline run: the coverage bootstrap and both flaky-detection runs. The
  two integration-level `DEFAULT_SUITE_TIMEOUT = 300.0` constants are gone;
  `Configuration::DEFAULT_SUITE_TIMEOUT` is the one default.
- A timed-out baseline reports "Configured test suite did not finish within
  N s while generating coverage; raise mutation.suite_timeout to allow more
  time", with the log path and tail; a failing suite keeps the old wording.
- Checked end to end: a project with a 5 s spec and `suite_timeout: 2`
  stops after 2 s with that message (exit 2).
- Not done: deriving the limit from a previous baseline's measured time.
