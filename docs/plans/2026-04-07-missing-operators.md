# Missing Mutation Operators: Gap Analysis & Implementation Plan

**Date:** 2026-04-07  
**Status:** Planned

## Background

Comparative analysis of henitai's operator set against mutant (Ruby), cargo-mutants
(Rust), infection (PHP), stryker-js (JavaScript), and stryker-net (.NET) revealed
five operator families present in all or most reference frameworks that henitai
does not yet implement.

The per-line cap (removed in ADR-08) previously suppressed the value of adding
granular operators. With exhaustive generation now in place, each new operator
contributes directly to mutation score.

henitai's current full set (15 operators) is closest to stryker-js (16). The gap
is largest against infection (~190 classes, including 47 stdlib-unwrap mutators)
and mutant (73 AST-node mutators).

---

## Gap: Missing Operator Families

### 1. UnaryOperator

**What it does:** Removes or inverts unary prefix operators.

| Original | Mutation |
|----------|----------|
| `!condition` | `condition` |
| `-x` | `x` |
| `~x` | `x` |

**Present in:** cargo-mutants, infection, stryker-js, stryker-net, mutant  
**AST nodes:** `:send` where method is `:!`, `:−@`, `:~`  
**Stryker name:** `UnaryOperator`

---

### 2. UpdateOperator

**What it does:** Swaps increment/decrement and compound assignment operators.

| Original | Mutation |
|----------|----------|
| `i += 1` | `i -= 1` |
| `i -= 1` | `i += 1` |
| `i *= 2` | `i /= 2` |
| `x ||= y` | `x &&= y` |
| `x &&= y` | `x ||= y` |

**Present in:** stryker-js, stryker-net  
**AST nodes:** `:op_asgn`  
**Stryker name:** `UpdateOperator` / `AssignmentOperator`  
**Note:** Partially overlaps with `ArithmeticOperator` for `+=`/`-=` but targets
the assignment form specifically, catching different test gaps.

---

### 3. RegexMutator

**What it does:** Mutates regular expression literals by altering quantifiers,
removing anchors, and replacing character classes.

| Original | Mutation |
|----------|----------|
| `/foo+/` | `/foo*/` |
| `/foo*/` | `/foo+/` |
| `/^foo/` | `/foo/` |
| `/foo$/` | `/foo/` |
| `/[a-z]/` | `/[^a-z]/` (negation) |

**Present in:** stryker-js, stryker-net, infection  
**AST nodes:** `:regexp` and `:regopt` children  
**Stryker name:** `Regex`  
**Note:** Requires inspecting the regex source string, not just the AST node type.

---

### 4. StringInterpolation

**What it does:** Empties string interpolation expressions and dynamic strings.

| Original | Mutation |
|----------|----------|
| `"hello #{name}"` | `""` |
| `"#{x} #{y}"` | `""` |

**Present in:** stryker-js (`StringLiteral` covers this), stryker-net
(`InterpolatedStringMutator`), infection  
**AST nodes:** `:dstr`  
**Stryker name:** `StringLiteral` (extend existing operator)  
**Note:** henitai's current `StringLiteral` handles `:str` nodes. Extending it
to cover `:dstr` is a small addition.

---

### 5. MethodChainUnwrap

**What it does:** Removes individual links from a method chain, replacing the
full chain with the receiver at the removed step.

| Original | Mutation |
|----------|----------|
| `list.select { \|x\| x > 0 }.map { \|x\| x * 2 }` | `list.select { \|x\| x > 0 }` |
| `list.select { \|x\| x > 0 }.map { \|x\| x * 2 }` | `list` |
| `array.uniq.sort.first` | `array.uniq.sort` |

**Present in:** infection (47 Unwrap mutators), stryker-net (`LinqMutator`),
mutant (per-send-node mutations)  
**AST nodes:** `:send` where receiver is also a `:send`  
**Stryker name:** `MethodExpression` (extend) or new `MethodChainUnwrap`  
**Note:** This is the highest-value operator for catching missing tests on
collection pipelines. It is also the most complex to implement correctly
because it needs to avoid unwrapping chains that break syntax (e.g. removing
a block argument when the outer call needs one).

---

## Implementation Plan

Each operator is independent and can be implemented in any order. Suggested
sequence prioritises signal value and implementation simplicity.

### Phase 1 — Quick wins (low complexity, high coverage value)

**1a. UnaryOperator**
- New file: `lib/henitai/operators/unary_operator.rb`
- `node_types`: `[:send]`
- Guard: only fire when method is `:!`, `:-@`, or `:~` with no arguments
- Mutation: remove the unary call, returning the receiver node
- Add to `Operator::FULL_SET`

**1b. StringLiteral extension for `:dstr`**
- Edit: `lib/henitai/operators/string_literal.rb`
- Add `:dstr` to `NODE_TYPES`
- In `mutate`: when node is `:dstr`, replace with `Parser::AST::Node.new(:str, [""])`

**1c. UpdateOperator (op-assign)**
- New file: `lib/henitai/operators/update_operator.rb`
- `node_types`: `[:op_asgn]`
- Swap table: `+` ↔ `-`, `*` ↔ `/`, `||` ↔ `&&`
- Mutation: rebuild the `:op_asgn` node with swapped operator
- Add to `Operator::FULL_SET`

### Phase 2 — Medium complexity

**2a. RegexMutator**
- New file: `lib/henitai/operators/regex_mutator.rb`
- `node_types`: `[:regexp]`
- Parse the regex source string; apply transformations:
  - `+` → `*`, `*` → `+` (quantifiers)
  - Strip leading `^` or trailing `$` anchors
  - Negate a character class `[x]` → `[^x]` (only when no existing negation)
- Each transformation yields a separate mutant
- Add to `Operator::FULL_SET`
- Edge cases: skip if transformed source is identical to original; validate
  the mutated string is a valid regex before emitting

### Phase 3 — Higher complexity

**3a. MethodChainUnwrap**
- New file: `lib/henitai/operators/method_chain_unwrap.rb`
- `node_types`: `[:send]`
- Only fire when the node's receiver is itself a `:send` node (chained call)
- Mutation: replace the outer send with its receiver (unwrap one link)
- Guard: skip if the outer node is the receiver of a block (`:block` parent),
  to avoid generating mutations that break the block argument
- This requires the visitor to pass parent context, or use a post-process
  step. Simpler first cut: only unwrap `:send` → `:send` chains where neither
  has a block argument
- Add to `Operator::FULL_SET`

---

## Acceptance Criteria

For each operator:

1. Unit spec covering: fires on the target node type, produces the expected
   mutated AST, does not fire on excluded cases.
2. Integration: operator appears in `henitai operator list --operators full`.
3. Rubocop clean.
4. No regressions in the existing suite.

For `MethodChainUnwrap` specifically: add at least one end-to-end spec using a
multi-step chain and verify that each link produces a separate surviving/killed
mutant result.
