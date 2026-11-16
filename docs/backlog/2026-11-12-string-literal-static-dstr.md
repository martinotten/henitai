# StringLiteral Emits an Equivalent Mutant for Strings Without Interpolation

Status: done (2026-11-13)
Date: 2026-11-12
Severity: Medium (guaranteed survivor noise, missing real mutations)
Source: ISeq TCE spike, `2026-11-12-iseq-trivial-compiler-equivalence.md`

## Summary

The Prism translation represents several plain strings as `dstr` nodes with
only `str` children: adjacent literals (`"a " "b"`), line-continued strings,
and multi-line heredocs without interpolation. `StringLiteral#mutate` sends
every `dstr` to `mutate_interpolated_string`. That method concatenates the
`str` children and emits "removed interpolation from string". With no
interpolation present, the result is the original string, so the mutant is
equivalent and survives every time.

Such strings also never receive the real string mutations (`""` and
`"Henitai was here"`) that plain `str` nodes get.

Evidence: the spike found 6 such mutants in `lib/` (for example
`lib/henitai/cli/run_options.rb:32`, `lib/henitai/execution_engine.rb:56`).
The current dogfood report has `Survived` "removed interpolation" mutants on
non-interpolated heredocs in `lib/henitai/cli.rb`,
`lib/henitai/cli/operator_command.rb` and `lib/henitai/integration.rb`.

## Proposed Behavior

- A `dstr` whose children are all `str` (recursively, for nested `dstr`
  parts) counts as a static string. Its value is the concatenation of the
  parts. It receives exactly the mutations of a plain string: the
  replacements in `REPLACEMENTS` that differ from that value.
- A `dstr` with at least one interpolation (`begin` child or other non-`str`
  part) keeps today's "removed interpolation" mutation.
- Operator name and stable-ID scheme are unchanged. The changed descriptions
  produce new stable IDs for the affected mutants, which is expected.

## Fix Plan (TDD)

1. **Red.** `spec/henitai/operators/string_literal_spec.rb`: adjacent
   literals and a non-interpolated `<<~` heredoc yield the `""` and
   `"Henitai was here"` mutants and no "removed interpolation" mutant.
2. **Red.** An interpolated string keeps exactly one "removed interpolation"
   mutant (existing examples stay unmodified).
3. **Green.** Branch on static vs interpolated `dstr` in `StringLiteral`.
4. Check that `StillbornFilter` accepts heredoc replacements (the mutant
   replaces a heredoc opener whose body sits outside the node's range).
   Smoke run on a heredoc subject.
5. Rubocop, steep, full suite, `rake oracle`.

## Acceptance

- No "removed interpolation" mutant for a `dstr` without interpolation.
- Static `dstr` strings receive the same mutations as `str` nodes.
- Oracle: no new false kills or survivors.
