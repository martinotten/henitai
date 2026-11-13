# Shard a Run Across CI Machines (`--shard k/n`)

Status: proposed
Date: 2026-11-12
Severity: Medium (CI latency on large codebases)
Source: optimization research 2026-11-12; cargo-mutants `--shard k/n` is the
only reviewed framework with cross-machine sharding (see
`docs/research/cross_framework_comparison.md`, "Sharding across machines")

## Summary

`jobs` parallelizes on one machine. A large codebase that needs more than one
runner has no way to split the mutant set across a CI matrix. A deterministic
`--shard k/n` partition lets `n` CI jobs each run a disjoint slice and a final
step merge the slices into one canonical report.

## Proposed Behavior

- `henitai run --shard K/N` (1-based `K`, `1 <= K <= N`) keeps only the
  mutants whose stable ID falls into shard `K` after generation, filtering
  and sampling, so the union of all shards is exactly the unsharded set.
- Partition key: SHA256 of `stableId` modulo `N` — stable under line drift
  and independent of generation order.
- Coverage bootstrap runs in every shard (each job needs the per-test map);
  CI can share it through the existing reports directory as a cache.
- A sharded run is non-authoritative: no trend `runs` row, no
  `completeFiles` claim for a file unless the shard holds all of its mutants.
- Each shard writes its partial report; the existing `CanonicalReportMerger`
  merges them by `stableId`. Add a documented merge step (CLI subcommand or
  documented sequence) for the final CI job.
- Exit codes: each shard's threshold is meaningless on a slice; the threshold
  is evaluated only on the merged report.

## Open Questions

- Merge entry point: new `henitai merge <reports...>` subcommand vs. running
  shards against one shared `reports_dir` artifact sequentially. Leaning:
  `henitai merge`, since CI shards run on separate machines.
- Should a shard exit `0` unconditionally (threshold deferred to merge), or
  still report framework errors (`2`)? Leaning: `2` stays, threshold codes
  move to the merge step.
- Interaction with `--incremental`: reused verdicts are partitioned the same
  way, so a warm cache (see `2026-07-13-ci-warm-verdict-cache.md`) works per
  shard without changes.

## Fix Plan (TDD)

1. **Red.** Unit spec for a `ShardFilter`: partition is disjoint, covers the
   whole set, is deterministic for a given `N`, and rejects invalid `K/N`.
2. **Green.** Implement it; wire it after sampling in the Runner pipeline.
3. **Red/Green.** CLI option parsing and `ConfigurationValidator` errors.
4. **Red/Green.** Runner marks sharded runs non-authoritative.
5. **Red/Green.** Merge entry point and threshold evaluation on the merged
   report.
6. Docs: README CLI section, `docs/architecture/architecture.md` pipeline,
   CI example with a matrix.

`--shard` and the merge entry point are user-visible options. Per "No
Parallel Implementations" in `AGENTS.md`, they need an ADR with an
**Execution paths** section before implementation. The shard filter should
be one more filtering stage in the existing pipeline, not a separate run
path, and the merge should reuse `CanonicalReportMerger`.

## Acceptance

- For `N = 3`, the merged report of three shards equals the unsharded report
  in mutant IDs and statuses.
- No shard writes trend rows or claims `completeFiles` for a partial file.
- `bundle exec rubocop`, `steep check`, full suite and smoke suites green.
