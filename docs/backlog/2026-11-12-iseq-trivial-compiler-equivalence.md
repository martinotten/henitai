# Trivial Compiler Equivalence on YARV Instruction Sequences (Spike)

Status: done (spike, 2026-11-12) — decision: do not build a TCE filter
Date: 2026-11-12
Severity: Low
Source: optimization research 2026-11-12; Papadakis et al. 2015 ("Trivial
Compiler Equivalence") report that comparing compiled output detects about
7–30 % of equivalent mutants in C programs, at almost no cost. Context:
[ADR-18](../architecture/adr/ADR-18-deferred-optimization-techniques.md).

## Question

If the original and the mutated method compile to the same YARV instruction
sequence (line numbers and trace events stripped), the mutant is equivalent
for every input. That rule is sound. Does it find enough equivalent mutants
in Ruby to justify a filter in `StaticFilter`? CRuby's compiler optimizes
little (peephole only), so the yield could be close to zero.

Go criterion set in advance: build the filter only if ISeq-identical mutants
make up at least about 2 % of the expected survivors.

## Method

A throwaway script (not committed) ran over every file in `lib/` except
`eager_load.rb`:

1. `SubjectResolver#resolve_from_files`, then
   `MutantGenerator#generate(..., sample: false)` for each operator set.
   Mutants suppressed by `StillbornFilter` were skipped.
2. For each mutant, the subject's `def` source was compiled twice, with
   `Unparser.unparse(original_node)` and with `Unparser.unparse(mutated_node)`
   spliced into the node's source range. Both sides went through Unparser, so
   formatting cannot cause a difference.
3. `RubyVM::InstructionSequence.compile(src).to_a`, normalized recursively:
   misc and node ids, paths, first line number, line numbers and event
   symbols in the bytecode were dropped. The instruction arrays, locals,
   params and catch table were compared.
4. Each comparison ran with a 5 s timeout. Unparse or compile failures were
   counted separately.

Runtime: about 50 s per operator set on Ruby 4.0.2.

## Results

| Operator set | Mutants | ISeq-identical | Compared as different | Unparser/Syntax errors | Timeouts |
| --- | ---: | ---: | ---: | ---: | ---: |
| light | 11,448 | 11 | 10,956 | 473 | 8 |
| full | 19,702 | 11 | 19,075 | 608 | 8 |
| hard | 20,363 | 11 | 19,736 | 608 | 8 |

All 11 hits come from light operators. None of them is flagged by
`EquivalenceDetector`.

| Hits | Operator | Case | Verdict |
| ---: | --- | --- | --- |
| 6 | StringLiteral | `"a " "b"` (adjacent literals) -> `"a b"` | genuinely equivalent; root cause in the operator (see below) |
| 4 | StringLiteral (1), ReturnValue (3) | `<<~RUBY` heredoc in `Integration#rspec_suite_runner_script` | not trustworthy: splicing a heredoc by its expression range leaves the body behind; spike artifact |
| 1 | LogicalOperator | `(@failed[path] \|\| false) \|\| failed` -> `(@failed[path]) \|\| failed` | genuinely equivalent; the peephole optimizer folds `\|\| false` before a further `\|\|` |

So 7 genuine hits in 11,448 light mutants, which is 0.06 %. Six of them
share one root cause that can be fixed at generation time. The dogfood
report's survivor rate (56 of 1,019, about 5.5 %) projects about 630
survivors for the full light run. Seven hits are about 1.1 % of those
survivors, and after the generation fix below, one hit is about 0.2 %.

## Decision

**No-go for a TCE filter.** The yield is below the go criterion. The only
cluster comes from an operator defect that is better fixed where it arises.
A filter would also need the exact activation source (`DefInjection`),
heredoc-safe splicing and a compile per mutant. That is a new
`StaticFilter` stage with its own failure modes, all for about one hit per
10,000 mutants.

**Follow-up:** `2026-11-12-string-literal-static-dstr.md`. The spike showed
that `StringLiteral` turns a `dstr` without interpolation (adjacent literals,
multi-line heredocs) into the same string. That is guaranteed survivor
noise. The dogfood report has `Survived` heredoc mutants of exactly this
kind (`cli.rb`, `operator_command.rb`, `integration.rb`).

## Revisit

Revisit if CRuby gains a more aggressive optimizer (for example, YJIT-level
folding exposed in the ISeq) or if a new operator produces systematic
ISeq-identical mutants. The method above can be reproduced in under an hour.
