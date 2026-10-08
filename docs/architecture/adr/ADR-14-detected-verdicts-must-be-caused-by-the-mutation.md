# ADR-14: Detected Verdicts Must Be Caused by the Mutation

Status: accepted

## Context

Henitai classified a mutant run from the child's exit status alone: `2` meant
`CompileError`, `0` meant `Survived`, and anything else meant `Killed`. In
practice, many harness failures produce a non-zero exit, and all of them were
counted as detections:

- an exception raised while activating the mutant, such as a `NameError` from
  loading a subject file whose superclass lives in another file;
- a child terminated by a signal (the OOM killer's `SIGKILL`, a segfault);
- activated code that was not the reported mutation: lost constant scope,
  `super` or `yield` inside `define_method`, keyword arguments re-rendered as
  a positional hash, a byte-offset splice after a multibyte character.

A `SystemExit` raised by the code under test went the other way: it ended the
child with status 0, which was counted as `Survived`.

The 2026-10-08 core review measured the effect
(`docs/reviews/2026-10-08-core-mutation-logic-review.md`). On the oracle
corpus, a suite without a single assertion produced 130 kills out of 137
mutants on 0.5.3. In Henitai's own dogfood run, 49 of 876 kills came from
mutants whose activated code was not the reported mutation.

For a mutation-testing tool, a false kill is the most harmful error. It
inflates the score and hides exactly the test gap the tool exists to reveal.

## Decision

A mutant counts as detected only when a test failed because of its mutation.
Anything else is a harness outcome, reported with its reason, and stays out
of the detected count.

1. **Fidelity before execution.** `FidelityCheck`, run by `StaticFilter`,
   verifies before execution that the activation source differs from the
   original method by exactly the reported mutation:
   - the activation source must be valid Ruby;
   - its re-parsed body must equal the original body with only the mutated
     node replaced;
   - syntax forms that the legacy AST cannot express (keyword arguments,
     one-parameter blocks) must be preserved.

   A mutant that fails is `CompileError` with `statusReason`, and it does not
   run.
2. **An explicit child report.** The mutant child writes a small JSON report
   next to its logs (`ChildReportStore`). The report records one of three
   outcomes: `activation_failed` (with the reason), `tests_finished` (with the
   exit code the tests returned), or `system_exit` (with the status).
   `MutantVerdict` classifies the run from the report and the process status:
   - `Killed` or `Survived` comes only from a finished test run;
   - a failed activation is `CompileError`;
   - a signal, a missing report, or a `SystemExit` raised during the tests is
     `RuntimeError`.

   The parent clears the report before every fork, so a retry cannot read
   the previous attempt's report. The baseline suite keeps exit-status
   semantics.
3. **A control run after execution.** `ControlRun`
   (`mutation.control_runs`, on by default) re-runs every subject that has a
   detected verdict, once, with its unmutated method injected through the
   same activation and fork path. If the tests fail, the injection itself
   broke them, and the subject's detected verdicts are reclassified as
   `CompileError`.
4. **Measured, not assumed.** `rake oracle` runs a corpus whose expected
   verdicts follow from its construction. It fails CI on any false kill or
   false survivor, and it reports the harness error rate.

## Consequences

- **Lower but honest scores.** Reported scores drop for projects whose kills
  were harness artifacts, including Henitai's own dogfood run. The CHANGELOG
  states this as an intended break.
- **Harness errors become visible.** They appear as `CompileError` or
  `RuntimeError` with a reason, so the tool's own limits show up in the report
  instead of hiding inside the score. On the oracle corpus most current harness
  errors come from activating before the test environment is loaded. ADR-13
  and the remediation plan's WS2 and WS4 address that.
- **Runtime cost of control runs.** They add one run per subject with
  detections. They can be switched off, and runs with heavy sampling have
  close to one mutant per subject, so there the cost approaches one extra run
  per mutant.
- **Statuses are no longer guessed from exit codes.** RSpec and Minitest still
  supply the test exit code, but the status itself now comes from the child's
  report.

## Related Documents

- [ADR-04](ADR-04-define_method-for-mutant-injection.md)
- [ADR-13](ADR-13-def-injection-in-lexical-nesting.md)
- [Core mutation logic review](../../reviews/2026-10-08-core-mutation-logic-review.md)
- [Core correctness remediation plan](../../plans/2026-10-08-core-correctness-remediation-plan.md)
