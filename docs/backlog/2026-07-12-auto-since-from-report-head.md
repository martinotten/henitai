# Auto-`--since` from the Report's Recorded HEAD

Status: proposed
Date: 2026-07-12
Severity: Low (convenience / cost reduction)
Source: discussion 2026-07-12; complementary to
[[2026-07-12-survivor-verdict-reuse-via-live-coverage]] per
`docs/architecture/adr/ADR-11-verdict-reuse-fingerprints-over-git-scoping.md`
(git picks the *scope*, fingerprints prove *reuse* within it — this ticket is
the scope half).

## Summary

Record the current git HEAD in the mutation report. On a later run, when the
recorded commit is an ancestor of the current HEAD, automatically apply
`--since <recorded HEAD>` so only files changed since the last verified run
are re-mutated — without the user having to remember the flag or the ref.
Fall back to an older report (or history rows) matching a known commit when
the newest report's commit is not in the current branch's history.

Automates an already-accepted workflow (manual `--since` + the existing
canonical-report merge for scoped runs) rather than adding new semantics.

## Problem

- `--since` is the cheapest cost-reducer henitai has, but it requires the user
  to supply the right ref. Wrong ref = wasted work or missed files.
- The report already merges scoped-run results into the canonical
  `mutation-report.json`; nothing records *which commit* a report reflects,
  so the natural ref ("whatever the last run verified") is not derivable.

## Soundness guard (mandatory — not optional polish)

Plain auto-`--since` would skip entire unchanged source files with **zero
validation of the test side**: a new spec that kills a survivor in an
untouched file would never re-run, and the merge would preserve the stale
Survived entry indefinitely. That is the false-negative failure mode ADR-11
exists to prevent. Manual `--since` is an explicit user opt-in to that risk;
*automatic* scoping must not make it the silent default. Therefore:

- **Any test-side change disables auto-scoping** (full run instead): changed
  files under `spec/`/`test/`, spec helpers/support, factories/fixtures,
  `Gemfile.lock`, `.henitai.yml`, `.rspec`. Detected from the same
  `git diff --name-only` output — no extra machinery.
- **Dirty worktree**: `GitDiffAnalyzer#changed_files(from:, to: "HEAD")`
  misses uncommitted edits. Either additionally diff against the worktree
  (`git diff --name-only <recorded>` without a `to`), or refuse auto-scoping
  when `git status --porcelain` is non-empty. Lean: include worktree changes
  in the diff; refuse only when the *report-side* state is unknowable.
- Mapping changed specs to affected subjects via per-test coverage (instead
  of bailing to a full run) is deliberately **out of scope** until the
  collector attribution fix from the survivor-reuse ticket lands — with
  first-toucher attribution the mapping under-selects, which is the unsafe
  direction. Revisit as a follow-up after Phase 0 ships.

## Proposed Behavior

- Reporter writes `gitHead` (full SHA) + `gitDirty` (bool) into the canonical
  report's metadata (vendor-extension field beside the existing metadata,
  same pattern as `stableId`).
- New opt-in flag `--auto-since` (and config key `auto_since: true`):
  1. Read `gitHead` from the canonical report (respecting `reports_dir`).
  2. `git merge-base --is-ancestor <gitHead> HEAD`? If not, walk older known
     commits: the `runs` table in `mutation-history.sqlite3` gains a
     `git_head` column, giving a list of candidate (commit, timestamp) pairs;
     pick the newest ancestor.
  3. No ancestor found, report missing, `gitDirty` recorded true, or the
     diff touches any guarded test-side path → **full run**, with a one-line
     terminal note explaining why auto-scope was skipped.
  4. Otherwise behave exactly as `--since <commit>` (existing code path,
     including the scoped-run report merge).
- Explicit `--since <ref>` always wins over `--auto-since`.
- Terminal summary states the derived ref: `auto-since: 7172590 (12 files
  changed)`.

## Non-Goals

- No verdict-level proof — that is the survivor-reuse ticket. This feature
  only chooses scope.
- No spec→subject impact mapping (see guard above; follow-up after Phase 0).
- No default-on this release; opt-in flag/config first, consider default
  after soak (same policy as `--incremental`).
- No cross-repo/monorepo path translation.

## Open Questions

- Where exactly in the Stryker schema to hang `gitHead` — top-level
  vendor-extension metadata vs. `framework` block. Follow whatever
  `stableId` vendoring precedent allows with the schema validator.
- Should `--auto-since` compose with `--incremental` automatically (both on
  = scope + reuse)? Lean yes — they are independent gates and ADR-11 frames
  them as composing; needs a combined smoke assertion.
- History fallback ordering when multiple reports/DB rows match ancestors of
  HEAD: newest commit by ancestry, or newest run by timestamp? Lean:
  ancestry distance (closest ancestor), tie-broken by run timestamp.

## Implementation Notes

- `lib/henitai/reporter.rb` — write `gitHead`/`gitDirty` metadata.
- `lib/henitai/git_diff_analyzer.rb` — add `head_sha`, `dirty?`,
  `ancestor?(sha)` helpers (thin wrappers over `rev-parse`,
  `status --porcelain`, `merge-base --is-ancestor`); worktree-inclusive diff
  variant.
- `lib/henitai/mutant_history_store.rb` / `sql.rb` — nullable `git_head`
  column on `runs` (additive ALTER, same pattern as the verdict-cache
  columns).
- New small collaborator (e.g. `AutoSinceResolver`) that owns the
  resolve/guard/fallback decision and returns either a ref or a
  reason-for-full-run; `Runner` consumes it where `@since` is read today.
  Keeps the guard logic unit-testable without git.
- `lib/henitai/cli/run_options.rb` — `--auto-since` flag;
  `configuration_validator` for the config key.
- Test-side guard path list shared with the survivor-reuse ticket's
  dependency-fingerprint file set — extract one definition, not two.

## Acceptance

- Opt-in only; without `--auto-since`/config, behavior byte-identical.
- Report carries `gitHead`/`gitDirty`; history `runs` rows carry `git_head`.
- Ancestor commit + source-only diff → run scoped exactly as manual
  `--since`, merge semantics unchanged, derived ref printed.
- Any guarded test-side change, dirty-unknowable state, missing/foreign
  report, or non-ancestor commit → full run with printed reason.
- Fallback selects the closest-ancestor known commit when the newest report
  doesn't match.
- Explicit `--since` overrides; composes with `--incremental`.
- Schema validator accepts the new metadata; existing reports without
  `gitHead` are handled (auto-scope skipped, no crash).

## Test Plan

| Layer | Coverage |
|---|---|
| Unit | reporter metadata emission; schema validation with/without `gitHead` |
| Unit | `AutoSinceResolver` decision matrix: ancestor/non-ancestor, dirty, test-side change, missing report, history fallback ordering |
| Unit | git helper wrappers with fake executor (exact command literals, per dashboard-metadata precedent) |
| Unit | store: `git_head` column migration + persistence |
| Unit | CLI flag + config key; explicit `--since` precedence |
| Smoke | rspec fixture: run, commit a source-only change, `--auto-since` run scopes to it; spec change forces full run |
| Regression | default path byte-identical; manual `--since` untouched |
