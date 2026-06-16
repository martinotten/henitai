# Replace `Minitest < Rspec` Inheritance With Composition

Status: backlog
Date: 2026-06-16
Severity: High
Source: 2026-06-16 structured review

## Summary

`Integration::Minitest` inherits from `Integration::Rspec`
(`lib/henitai/integration.rb:823`). The Minitest adapter therefore inherits every
RSpec-specific method and overrides only a subset. The architecture docs
describe the two as sibling adapters behind a common `Base` interface; the code
makes Minitest a subtype of RSpec.

## Problem

- `class Minitest < Rspec` (line 823) means `run_rspec_runner`,
  `build_rspec_runner`, `configure_rspec_runner`, `load_rspec_spec_files` are all
  inherited into the Minitest path.
- Any change to RSpec internals can silently break Minitest with no compile-time
  or test signal.
- The relationship contradicts `docs/architecture/architecture.md`, which lists
  `Rspec` and `Minitest` as peers.

## Fix Plan

Depends on / coordinates with the `integration.rb` decomposition issue.

1. **Lock behavior.** Add or confirm specs that exercise the Minitest adapter's
   public surface (`spawn_mutant`, `build_result`, spec-file resolution) so the
   refactor is behavior-preserving.
2. **Identify the shared contract.** List methods `Minitest` actually relies on
   from `Rspec`. Decide which are framework-agnostic (belong in `Base`) vs
   RSpec-only (belong in `Rspec`).
3. **Promote shared logic to `Base`.** Move framework-agnostic helpers down into
   `Base`. Move RSpec-only runner logic into `Rspec` (or a `RspecRunnerSupport`
   mixin included by `Rspec` only).
4. **Reparent.** Change to `class Minitest < Base`. Implement the Minitest
   runner explicitly; do not borrow RSpec methods.
5. **Verify isolation.** Add a spec asserting a Minitest instance does NOT
   respond to RSpec-only methods (`run_rspec_runner` etc.), preventing
   regression.

## Acceptance

- `Minitest` no longer inherits from `Rspec`.
- Minitest instance does not expose RSpec-specific methods.
- Both integration suites green; behavior unchanged.

## Related

- [[2026-06-16-review-integration-god-file]]
