# Warm Verdict Cache in GitHub CI

Status: proposed
Date: 2026-07-13
Severity: Medium (CI cost/latency)
Source: discussion 2026-07-13, after survivor verdict reuse (PR #19,
ADR-11) made `--incremental` skip both killed and survived verdicts.

## Summary

The CI mutation gate currently starts cold on every run: no
`reports/mutation-history.sqlite3`, so `--incremental` has nothing to
reuse and every in-scope mutant executes. Locally a warm cache turns a
7s scoped run into 0.29s; CI should get the same effect. Two candidate
mechanisms: commit the warm data to the repo, or use `actions/cache`.

## Options

### Option A — `actions/cache` (recommended)

Cache `reports/mutation-history.sqlite3` keyed by branch with fallback to
the main-branch cache:

```yaml
- uses: actions/cache@v4
  with:
    path: reports/mutation-history.sqlite3
    key: henitai-history-${{ github.ref_name }}-${{ github.sha }}
    restore-keys: |
      henitai-history-${{ github.ref_name }}-
      henitai-history-main-
```

- Correctness is carried by the fingerprints, not the cache freshness:
  a stale cache only means fewer reuses (fingerprint mismatch → re-run),
  never a wrong verdict — the exact property ADR-11 guarantees.
- The main-branch run after each merge repopulates the shared baseline.
- No repo churn; cache eviction (7-day GitHub TTL / 10 GB budget) merely
  degrades to today's cold behavior.
- Needs `--incremental` added to the CI invocation; keep `--force`
  documented as the manual override, and consider a scheduled weekly
  cold run (`--force`) as drift canary comparing combined vs
  executed-only scores.

### Option B — commit warm data to the repo

Commit `reports/mutation-history.sqlite3` (or an exported subset) after
full main runs, e.g. via a bot commit or release step.

- Pro: deterministic, survives cache eviction, also warms fresh clones
  and local contributors.
- Con: binary sqlite churn in git history on every main build; merge
  conflicts are unresolvable (binary), so it must be regenerate-only;
  PR diffs get noisy unless the file is updated exclusively by a bot on
  main. If pursued, prefer a periodic (weekly/release) refresh commit
  over per-merge, and mark the path with `linguist-generated` +
  `-diff` in `.gitattributes`.

Lean: Option A first — all the benefit, none of the churn. Revisit B only
if cache eviction proves painful in practice.

## Prerequisites / interactions

- CI must not run smoke suites before the mutation gate in the same job
  without accounting for the dependency fingerprint — smoke artifacts are
  already pruned from it (GENERATED_DIR_SEGMENTS), so this is handled.
- The advisory mutation gate's empty-run exit-0 behavior (test-only PRs)
  already exists; verify a fully-cached run (0 executed, all reused)
  also exits 0 and reports the reused split.
- Consider uploading the HTML report as a workflow artifact when reuse
  changes the executed-only vs combined scores, for auditability.

## Acceptance

- PR CI mutation gate reuses verdicts from the most recent main run
  (log line `N of M verdicts reused from history (K killed, S survived)`
  with N > 0 on a doc-only change).
- Cold cache (evicted) degrades gracefully to a full run, exit codes
  unchanged.
- Weekly cold run exists as drift canary.
