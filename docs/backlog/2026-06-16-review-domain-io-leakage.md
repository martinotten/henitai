# Stop Domain Objects From Doing Direct IO

Status: done
Date: 2026-06-16
Severity: Medium
Source: 2026-06-16 structured review

## Summary

The architecture docs claim clean boundaries with infrastructure at the edges
and dependencies pointing inward. Two analysis/reporting objects break that by
reaching directly into the filesystem and SQLite.

## Problem

- `lib/henitai/result.rb:133`: `build_files_section` calls
  `File.read(file_mutants.first.location[:file])`. `Result` is described as a
  domain/analysis value object, yet it reads source files from disk — making it
  untestable without real files and coupling domain to IO.
- `lib/henitai/reporter.rb:301`: `Reporter::Json` instantiates
  `MutantHistoryStore.new(path:)` itself. The docs separate "Reporters" from
  "Persistence"; a reporter should receive trend data or a store, not build the
  SQLite-backed infrastructure object internally.

## Fix Plan

1. **`Result` source reads.**
   - Add a spec proving `Result` can build its files section from injected
     source content (no disk).
   - Introduce a small `SourceProvider` (or pass already-read source into
     `Result`) so the caller — which already knows file paths — supplies
     contents. `Result` consumes data, performs no IO.
   - Update the construction site to read files once and inject.
2. **`Reporter::Json` store coupling.**
   - Change `Reporter::Json` to accept a history store (or pre-computed trend
     data) via its initializer.
   - Move `MutantHistoryStore` construction up to the runner/composition root
     that already owns wiring.
   - Spec the reporter against a fake/in-memory store double.
3. Run full suite; confirm reporters and result analysis behave identically.

## Acceptance

- `Result` performs no `File.read`; specs run without touching disk for source.
- `Reporter::Json` receives its store/trend data; does not `new` infrastructure.
- Dependency direction matches `docs/architecture/architecture.md`.

## Related

- [[2026-06-16-review-class-size-discipline]]
