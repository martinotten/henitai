# CI-Native Annotation Reporter (GitHub Actions)

Status: done (2026-07-08)
Date: 2026-07-02
Severity: Low
Source: feature-parity comparison against `cargo-mutants`;
evidence extended 2026-07-06 by the cross-framework round
(`docs/research/cross_framework_comparison.md` §2.7)

## Summary

`cargo-mutants` emits `::error file=...,line=...::message`-style GitHub
Actions annotations automatically when `$GITHUB_ACTIONS` is set (or via
`--annotations=github`), so survived mutants show up inline on the PR diff
in the GitHub UI. Henitai's reporters (`Terminal`, `Json`, `Html`,
`Dashboard`) all require opening a separate report; nothing surfaces
directly on the PR.

## Problem

`Reporter.reporter_class`/`Reporter.run_all` (`lib/henitai/reporter.rb`)
resolve `config.reporters` to one of four fixed classes. None of them target
a CI annotation format. For a PR-triggered `henitai run --since origin/main`
in CI, a developer currently has to open the HTML report or scroll CI logs
to find which lines survived — there's no inline, per-line signal on the
diff itself the way `rubocop`/`cargo-mutants`/most linters provide.

## Cross-Framework Evidence (added 2026-07-06)

- **Infection 0.34** ships both a `github` logger (`--logger-github`, GitHub
  Actions annotations) and a `gitlab` logger (Code Climate/codequality JSON)
  — precedent for the reporter-class shape proposed below, and for treating
  GitLab as a follow-up logger rather than an abstraction requirement.
- **StrykerJS has no CI annotation reporter at all** (exit codes + dashboard
  badge only) and in the **PIT** ecosystem PR annotations are
  commercial-only (arcmutate). Landing this makes henitai's CI story
  stronger than both incumbents' OSS offerings, not just at parity with
  cargo-mutants.

## Proposed Behavior

A new `Reporter::GithubAnnotations` class (or similar name) that, for each
`Survived` mutant in the result, prints a GitHub Actions workflow command to
stdout:

```
::warning file=lib/foo.rb,line=42::Survived mutant: ArithmeticOperator — `a + b` -> `a - b` not caught by any test
```

- Only survived (and, at the operator's discretion, timeout) mutants
  produce annotations — killed/no-coverage/ignored mutants stay silent to
  avoid flooding the PR with noise.
- Auto-detected via `ENV["GITHUB_ACTIONS"]` so no config change is required
  for GitHub-hosted CI, mirroring `cargo-mutants`' behavior; also
  addable explicitly via `config.reporters` for local testing or other CI
  systems that consume the same command syntax.

## Suggested Interface

```yaml
reporters:
  - terminal
  - github   # new
```

or zero-config auto-detection when `GITHUB_ACTIONS=true` is present,
appending itself to whatever reporters are already configured.

## Non-Goals

- Not building a general CI-annotation abstraction for GitLab/other
  providers in the first pass — GitHub Actions only, since that's this
  repo's own CI (`.github/workflows/`).
- Not replacing the Stryker Dashboard integration — complementary, not
  competing (dashboard is the historical/trend view, annotations are the
  inline PR-review nudge).

## Open Questions

- Auto-detection default-on in CI vs. requiring explicit opt-in via
  `reporters:` — auto-on matches `cargo-mutants`' ergonomics but changes
  CI output shape for existing henitai users without an explicit
  config change; needs a decision before implementing.
- Should `NoCoverage` mutants also annotate (a different signal — "this
  line isn't exercised by any test at all" rather than "a mutation
  survived")? Worth a separate annotation class/severity
  (`::notice` vs `::warning`) if included.

## Implementation Notes

- `lib/henitai/reporter.rb` already has the `Base` class pattern
  (`report(result)`) that `Terminal`/`Json`/`Html`/`Dashboard` implement —
  the new class follows the same shape.
- `Result#mutants` (via `survived?`) and `mutant.location` already carry
  everything needed (`file`, `start_line`) for the annotation payload; no
  new *data* plumbing required. There is still config-surface plumbing:
  `Reporter.reporter_class`'s name→class map needs the new entry (it
  raises `ArgumentError, "Unknown reporter: ... Valid reporters: terminal,
  json, html, dashboard"` on unknown names today — the error message is the
  only allowlist and must list the new name). Neither
  `assets/schema/henitai.schema.json` (plain `array` of `string`, no enum)
  nor `ConfigurationValidator::Rules.validate_reporters` (string-array
  type check only) enumerates valid reporter names, so no schema/validator
  change is strictly required — though adding a schema `enum` would be a
  natural companion change.

## Decisions (resolving the Open Questions)

- **Explicit opt-in first release** — no `GITHUB_ACTIONS` auto-detection.
  Changing existing users' CI output shape silently is the wrong default;
  auto-on can follow as a separate, announced change once the format has
  soaked. (Matches the recommendation recorded 2026-07-02.)
- **Survived only in v1.** No `NoCoverage`/`Timeout` annotations — separate
  signal, separate follow-up if wanted.

## Fix Plan (TDD)

1. **Red.** `spec/henitai/reporter/github_annotations_spec.rb`: given a
   result with survived, killed, ignored and no-coverage mutants, `#report`
   writes exactly one line per survived mutant to its output IO:
   `::warning file=<relative path>,line=<start_line>::Survived mutant:
   <operator> — <description>`. Assert: killed/ignored/no-coverage are
   silent; zero survivors → zero output; message payload is
   workflow-command-escaped (`%` → `%25`, `\n` → `%0A`, `\r` → `%0D` — GH
   parses the rest literally); file path is repo-relative, not absolute.
2. **Green.** Implement `Reporter::GithubAnnotations` following the
   existing `Base#report(result)` shape, injected IO (default `$stdout`)
   per this repo's DI conventions.
3. **Red.** `reporter_spec.rb`: `Reporter.reporter_class("github")`
   resolves; unknown-name `ArgumentError` message now lists `github`.
4. **Green.** Add the map entry + error-message update; optional schema
   `enum` companion.
5. **Dogfood.** Add `github` to this repo's own CI mutation job
   (`.github/workflows/ci.yml` step or `.henitai.yml` reporters) — the
   next PR with a survivor proves it end-to-end.
6. Refactor, full suite, rubocop.

## Acceptance

- `reporters: [terminal, github]` in `.henitai.yml` emits one `::warning`
  workflow command per survived mutant with correct relative file + line;
  nothing else annotates.
- Zero survivors → zero annotation lines; exit codes completely unchanged.
- Payload escaping proven against a description containing `%`, newline,
  and `::`.
- Unknown-reporter error message includes `github`.
- Without `github` configured: output byte-identical to today.
- Own CI mutation job runs with the reporter enabled (dogfood wiring
  committed).

## Test Plan

| Layer | Coverage |
|---|---|
| Unit | `github_annotations_spec.rb`: status filtering, line format, escaping matrix, relative-path handling, empty result |
| Unit | `reporter_spec.rb`: name resolution + allowlist error message |
| Integration | rspec smoke fixture: deliberately-surviving mutant scenario, run with `reporters: [github]`, assert stdout contains `::warning file=` |
| Infra | `spec/infra` CI-workflow spec updated if the workflow file changes |
