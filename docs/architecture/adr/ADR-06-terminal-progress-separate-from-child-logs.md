# ADR-06: Terminal Progress Separate from Child Logs

Status: accepted

## Context

Henitai currently forwards the RSpec child process output directly to the
terminal. That makes the live run noisy, mixes test diagnostics with progress
updates, and makes the terminal harder to read in CI.

Mutation testing frameworks in the ecosystem usually separate these concerns:
progress stays on the console, while raw test output is captured as an artifact
or printed only when a scenario fails.

## Decision

Henitai will separate progress output from child process logs.

- The parent process owns live progress and the final terminal summary.
- Child stdout and stderr are captured per scenario and written to log files
  under `reports_dir`.
- The terminal only prints a short tail of the captured log when a baseline or
  mutant fails, unless the user explicitly requests full logs.
- Full child output is available through an opt-in verbose mode such as
  `--all-logs`.
- Non-TTY output uses append-only progress instead of cursor-based rendering.

## Consequences

- The terminal stays readable during long runs.
- Raw test output becomes a durable artifact instead of ephemeral terminal
  noise.
- The execution engine must carry captured output and log metadata through the
  result pipeline.
- Specs must cover the default quiet path, failure log tails, full-log opt-in,
  and non-TTY fallback behavior.

## Related Documents

- [Architecture overview](../architecture.md)
- [Implementation plan](../../plan/implementation_plan.md)
- [ADR index](README.md)
