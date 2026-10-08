# ADR-13: `def` Injection in the Original Lexical Nesting

Status: proposed (supersedes ADR-04 once accepted)

## Context

ADR-04 chose `Module#define_method` for mutant injection. Its drivers were no
disk I/O per mutant and no concurrent file writes. Evaluating a `def` string in
memory meets both drivers equally well, so the drivers do not decide between
the two in-memory options.

The current implementation evaluates `define_method(:m) do |params| body end`
through a string `class_eval` on the target. That differs semantically from
the original method in several ways. All of them were reproduced in the
2026-10-08 review (`docs/reviews/2026-10-08-core-mutation-logic-review.md`,
ACT-01 to ACT-08):

| Aspect | Original `def` | `define_method` through string `class_eval` |
|---|---|---|
| Constant lookup | lexical nesting of the source, e.g. `[Outer::Inner, Outer]` | the target plus the activator's own nesting, e.g. `[Outer::Inner, Henitai::Mutant::Activator, Henitai::Mutant, Henitai]` |
| Class methods | class scope | singleton-class scope: own constants and `@@vars` are not found |
| Implicit `super` | allowed | `RuntimeError` |
| `yield`, `block_given?` | the method's block | `LocalJumpError`, or always `false` |
| Parameters | the original signature | rebuilt as a block signature: `...`, anonymous `*`/`**`/`&` forwarding, destructuring and `**nil` break |
| `__FILE__`, `__LINE__` | the source file | `activator.rb` |
| `frozen_string_literal` | honoured | lost |
| Visibility | preserved | public |

Each divergence makes tests fail for a reason unrelated to the mutation, so it
is reported as `Killed`, an inflated score. Henitai's dogfood run masks
the constant-lookup defect, because Henitai's own constants resolve through
the leaked nesting.

## Decision

1. **Inject the mutated method as a real `def`, wrapped in the original lexical nesting.**
   - The subject resolver records the enclosing `module`/`class`/`class << self` nodes, including the compact `class A::B` form.
   - The activator emits the same nesting with the keyword that matches the runtime object, and evaluates it with `TOPLEVEL_BINDING.eval(source, original_file, line)`, so that the `def` line maps to its original line.
   - The source file's magic comments are preserved.
2. **Copy the original `def` header verbatim and splice the mutation inside the full `def` source range,** including default values and heredoc bodies.
3. **Capture the visibility and the `module_function` state before injection, and re-apply them afterwards.**
4. **Activate after the test environment has loaded** (see remediation plan WS2 and WS4), so that every constant the method refers to already exists.
5. **Keep `define_method` only as a fallback** for subjects that cannot be reopened: `define_method` subjects, methods inside `Struct.new`/`Data.define` blocks, and `class << obj`. Mutants activated through the fallback are marked in the report.
6. **Guard every activation with the static fidelity check** (plan WS0): parse the activation source and diff it against the original. Any difference other than the reported mutation becomes a harness status, never a test run.

## Consequences

- **Correct semantics:** constant lookup, `super`, `yield`, `block_given?`, parameter semantics, `__FILE__`/`__LINE__` and `frozen_string_literal` match the original method. The ACT-01, ACT-02, ACT-03 and ACT-07 class of false kills disappears.
- **Less code:** `Mutant::ParameterSource` is no longer needed on the primary path.
- **Recipe format change:** the format of precomputed activation sources changes, so the recipe format version must be bumped to invalidate cached recipes.
- **Visibility is now explicit:** it must be re-applied, because a re-opened `def` is public by default.
- **Redefinition warnings:** "method redefined" warnings must be silenced, as they already are through `WarningSilencer`.
- **Aliases unchanged:** aliases created with `alias_method` still point to the original body, as before. This is a known limitation of both approaches.
- **Dependency on load order:** relying on the environment being loaded before activation makes this ADR depend on the execution-order change in the remediation plan (WS2.5 and WS4).
- **Lower scores:** reported scores will drop for projects that were affected. This is intended, and the CHANGELOG must say so.

## Related Documents

- [ADR-04](ADR-04-define_method-for-mutant-injection.md)
- [Core mutation logic review](../../reviews/2026-10-08-core-mutation-logic-review.md)
- [Core correctness remediation plan](../../plans/2026-10-08-core-correctness-remediation-plan.md)
