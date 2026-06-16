# Structured Review Findings — 2026-06-16

Status: in progress
Date: 2026-06-16

Backlog issues from the 2026-06-16 in-depth structured review (multi-agent,
findings re-verified). Each linked file contains the problem statement and an
embedded fix plan (TDD steps, target files, acceptance criteria).

Status column reflects work landed on PR #2
(`docs/review-findings-2026-06-16`): done = committed and verified, partial =
some scope addressed, open = not started.

## Issues by priority

| Sev | Status | Issue | Theme |
|-----|--------|-------|-------|
| High | done | [[2026-06-16-review-integration-god-file]] | Architecture — split 953-line `integration.rb`, dedup `ScenarioLogSupport`/`suppress_simplecov!` |
| High | done | [[2026-06-16-review-minitest-inherits-rspec]] | Architecture — replace `Minitest < Rspec` with composition |
| High | partial | [[2026-06-16-review-test-overmocking-and-gaps]] | Tests — de-mock `runner_spec`, cover 11 spec-less files (only `scenario_log_support` coverage landed) |
| High | done | [[2026-06-16-review-gemspec-stale-uri]] | Packaging — stale `source_code_uri`, Ruby version mismatch (low effort) |
| Med | done | [[2026-06-16-review-flaky-count-parallel]] | Correctness — flaky count always 0 in parallel mode |
| Med | open | [[2026-06-16-review-class-size-discipline]] | Architecture — remove `Metrics/*Length` rubocop disables |
| Med | open | [[2026-06-16-review-domain-io-leakage]] | Architecture — `Result`/`Reporter::Json` do direct IO |
| Med | open | [[2026-06-16-review-flaky-timing-specs]] | Tests — remove `sleep`/`Dir.chdir` flakiness |
| Med | open | [[2026-06-16-review-doc-debt]] | Docs — README operator gap, consolidate plan trees |
| Low | done | [[2026-06-16-review-repo-hygiene]] | Hygiene — gitignore graphify, clean stray artifacts |
| Low | open | [[2026-06-16-review-lenient-dogfood-config]] | Quality — tighten `.henitai.yml` self-run |
| Low | done | [[2026-06-16-review-dead-rescue-and-branch]] | Correctness — narrow broad rescues, dead draining branch |

## Suggested sequencing

1. Quick win: gemspec/version (`review-gemspec-stale-uri`) + hygiene gitignore.
2. Correctness: flaky-count-parallel, dead-rescue-and-branch.
3. Architecture core: integration-god-file → minitest-inherits-rspec →
   class-size-discipline → domain-io-leakage (they interlock; do in this order).
4. Tests: test-overmocking-and-gaps + flaky-timing-specs alongside the arch work.
5. Docs + dogfood: doc-debt, lenient-dogfood-config last (depend on prior fixes).

## Note on validation

One initial agent flag — a "Critical" nil-deref at
`process_worker_runner.rb:346` — was downgraded after review: the draining
branch is unreachable dead code, not a live crash. Captured in
[[2026-06-16-review-dead-rescue-and-branch]].
