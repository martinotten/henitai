# Mistakes

What went wrong, why, and what stops it recurring. Newest first.

## 2026-08-21 — `git add -A` committed an untracked tool artifact

**What happened.** The release plan said explicitly: "Untracked `.pi/` in the
working tree is an unrelated tool artifact — do not commit it." Several commits
later I staged with `git add -A` and swept `.pi/extensions/rtk.ts` (80 lines of
local agent tooling) into the commit that followed the release commit. Caught
only when asked whether anything was broken, by diffing the branch against the
release commit rather than trusting `git status`.

**Root cause.** `git add -A` stages everything untracked, including the exact
file I had been told to leave alone. `git status` looked clean *afterwards*,
which is the trap: a clean status means nothing is unstaged, not that nothing
wrong is staged.

**Prevention.** Stage explicit paths, not `-A`, whenever the working tree has
untracked files that are not part of the change. Before committing on a release
branch, run `git diff <last-known-good> HEAD --stat` and read the file list —
`git status` cannot show what a previous commit already absorbed. And when a
plan names a file to exclude, gitignore it at that moment instead of relying on
remembering; `.pi/` is now in `.gitignore`.

## 2026-08-21 — A ported spec can be vacuous even though it was green before

**What happened.** The 0.5.0 collaborator extractions moved examples out of
host specs into specs for the new classes. Six of the ported examples proved
nothing once moved, and at least one had proved nothing where it started:

- `LoadedFeatures#normalize`'s `rescue StandardError` — the original example
  used a feature string that matched a candidate *raw*, so `||` short-circuited
  and `#normalize` never ran. The example passed with the rescue deleted, in the
  old code as well as the new.
- `ChildDebugLog#mutant_meta` and `#activation_check` early returns — `#write`
  gates on `enabled?` internally, so an output-only assertion passed with the
  guard removed.
- `ChildDebugLog#write` reading `$stdout` late — `output(...).to_stdout` swaps
  the global *before* the block runs, so the example passed with the stream
  captured at construction, which is the actual bug it was written to prevent.
- `RunnerDependencies#progress_reporter` "passes `full_run` on every call" — the
  stub returned `nil`, and an `||=` memoization re-evaluates on `nil`, so the
  example passed with the method memoized.
- `SourceFileSelection#call` exclude/narrow ordering — I documented the ordering
  as load-bearing. It is not: both stages are filters over the same list and
  they commute. The comment asserted a guarantee that did not exist.

**Root cause.** Green is not evidence that a spec constrains anything. A
passing example proves the code and the assertion agree today, not that the
assertion would notice if the code changed. Short-circuit operators, internally
gated helpers, nil-returning stubs and matchers that mutate global state before
the block runs all produce examples that cannot fail.

**Prevention — falsify every new or moved spec.** Break the implementation on
purpose, one mutation at a time, and confirm the spec goes red. Cheaply:

```sh
cp lib/henitai/thing.rb /tmp/thing.bak
perl -pi -e 's/<the rule>/<a plausible mutation>/' lib/henitai/thing.rb
bundle exec rspec --options /dev/null -r ./spec/spec_helper.rb spec/henitai/thing_spec.rb
cp /tmp/thing.bak lib/henitai/thing.rb
```

`--options /dev/null -r ./spec/spec_helper.rb` skips `.rspec`'s whole-tree
pattern, which makes the loop seconds instead of half a minute.

When a mutation does not go red, decide which it is and say so in writing:

- **A coverage gap** — fix the spec. Assert the *work not done*, not just the
  absent output: "the mutant is never interrogated", "`RSpec.world` is never
  called", "`File.expand_path` is never called".
- **A genuinely equivalent mutation** — record it in the ticket so the survivor
  is not mistaken for a gap later. Two shipped in 0.5.0:
  `SlotDeadline`'s `remaining.positive?` versus `remaining >= 0` (identical at
  the boundary), and `TestFileSelection`'s `key?` versus truthiness (differ only
  for an explicitly-nil resolver no caller produces).
- **A wrong comment** — fix the comment, not the code.

This is the substitute for the per-step mutation-score gate whenever that gate
cannot run.

## 2026-08-21 — A default-on child watchdog trusted primitives the host suite stubs

**What happened.** `OrphanWatchdog` decides it has been orphaned via
`Process.ppid` and `Process.kill(0, pid)`. A mutant child runs the *host
project's own suite*, and henitai's suite stubs `Process.kill` to raise `ESRCH`
in several places. When the watchdog's poll landed inside such an example, it
concluded the parent was dead and called `exit!(2)` — which the scheduler
records as `CompileError`.

Measured on a 1019-mutant dogfood run: two mutants were misreported as
`CompileError` and one as `Timeout`; all three are `Killed`. The watchdog fired
seven times, four of them false positives.

**Root cause.** Any Ruby-level call in code that runs inside the mutant child is
stubbable by the suite under test. A watchdog whose decision depends on such a
call is not measuring the OS, it is measuring the suite.

**Prevention.** Capture the primitive at load time:
`KILL = Process.method(:kill)`, `PPID = Process.method(:ppid)`. A `Method` object
keeps pointing at the original definition after the singleton method is
redefined, so `allow(Process).to receive(:kill)` cannot reach it. Both are now
spec'd directly ("is not fooled by a stubbed `Process.kill`"), and the injection
point moved from a stub to a keyword argument so the error branches stay
testable.

Generally: **anything running inside the mutant child must not depend on
stubbable global state.** The gate cannot catch this — the unit suite is exactly
the thing doing the stubbing. It took an instrumented dogfood run (temporary
`on_orphan` that logged every firing with its mutant id) to see it at all.

## 2026-08-21 — Scoped `henitai run` silently reports zero mutants

**What happened.** The 0.5.0 plan gated every extraction on a scoped mutation
score: capture `henitai run 'Henitai::Thing#*'` before, compare after. Every
scoped run returned `MS n/a`, 0 killed, 0 survived, 0 no-coverage. I first
suspected the `sampling.ratio: 0.05` in `.henitai.yml` and re-ran with sampling
forced to `1.0`; still zero.

**Root cause.** Part 2 of
`docs/backlog/2026-07-08-per-test-coverage-completeness-check.md`, still open:
`reports/henitai_per_test.json` is scope-replacing, not additive, and
`per_test_coverage_ready?` gates on mtime freshness plus mere existence. A
per-test map left by an earlier scoped run reads as fresh and available for a
completely different scope, so the bootstrap is skipped and every mutant is
classified `NoCoverage` — in under a second, with no warning.

**Prevention.** A scoped run that finishes suspiciously fast with an all-`n/a`
summary is not a passing gate, it is a broken one. Either `henitai clean` first
and accept the full bootstrap, or state plainly that the gate could not run and
name the substitute. Do not report an empty result as a pass.

## 2026-08-21 — A new default-on child behavior killed the suite with no output

**What happened.** After wiring `OrphanWatchdog` into the fork site,
`bundle exec ruby bin/verify-process-free-specs` exited 2 with no failure list
and no example summary. The plain `bundle exec rspec` was green.

**Root cause.** `spec/henitai/integration/rspec_spec.rb` and its Minitest
sibling stub `Process.fork` to run the block *in-process* (21 call sites), so
`ChildBootstrap.after_fork!` executed inside the test process with
`parent_pid` set to that process's own pid. `Process.ppid != parent_pid` was
therefore true, the watchdog concluded it had been orphaned, and `exit!(2)`
took RSpec down before it could report anything.

**Prevention.** Any new behavior installed in the fork child has to be checked
against the specs that execute the fork block in-process — grep for
`stub_process_fork` and `allow(Process).to receive(:fork)`. And run the guarded
lane (`bin/verify-process-free-specs`), not only `bundle exec rspec`: only the
guarded lane caught this.
