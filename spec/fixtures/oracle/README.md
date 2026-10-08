# Oracle corpus

A small project whose expected mutation verdicts follow from its construction,
used by `bundle exec rake oracle` to measure how reliable Henitai's verdicts are.

- `lib/oracle/` holds one method per construct that broke mutant fidelity or
  classification in the 2026-10-08 core review (`docs/reviews/`); each method's
  comment names the finding.
- `spec/weak/` calls every method, asserts nothing and swallows every
  exception. No mutant can legitimately fail it, so every Killed or Timeout
  verdict in weak mode is a **false kill**.
- `spec/strong/` pins every method's behaviour. Every survivor must be listed
  with its reason in `expected.yml`; any other survivor is a **false
  survivor**.

The task also reports the **harness error rate**: the share of mutants Henitai
could not run faithfully (CompileError, RuntimeError), grouped by reason. It
is informational: an honest harness error is better than a false verdict, but
it is a mutant the tool cannot test yet.
