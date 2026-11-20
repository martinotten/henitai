# Mutate Logic in Rails Class Macros

Status: proposed (needs a spike before planning)
Date: 2026-11-13
Severity: Medium (a large share of Rails model logic is never mutated)
Source: requirement intake 2026-11-12; verified 2026-11-13 with
`SubjectResolver#resolve_from_files` on a sample model.

## Summary

Subjects are method definitions (`def`, `define_method`, methods in
`Struct.new`/`Data.define`/`Class.new` blocks). In Rails models a lot of
behaviour lives in class-body macro calls instead — scope lambdas,
validation options, callback conditions. None of it is mutated today, so a
model can reach a high score while its query and validation logic is
untested.

## Evidence

Sample model:

```ruby
class User
  scope :active, -> { where(active: true).where("age > ?", 17) }
  validates :name, presence: true, length: { maximum: 50 }
  before_save :normalize, if: -> { name.present? && changed? }

  def adult?
    age >= 18
  end
end
```

`SubjectResolver` returns exactly one subject: `User#adult?`. The scope
lambda, the validation options and the callback condition produce no
subjects and therefore no mutants.

## Why this is not a small change

Class-body code runs once, at load time. Henitai activates a mutant after
the tests are loaded by re-evaluating the subject's `def` in its lexical
scope (ADR-13). A macro cannot simply be re-evaluated:

- `scope :active, -> { … }` redefined with a mutated lambda probably
  replaces the scope (to verify per Rails version);
- `validates …` called again *adds* a second validator next to the original,
  so original and mutant run together — a false survivor or false kill;
- callbacks behave like validations (appended, not replaced).

ADR-14 requires that the activated code is exactly the mutation; an
activation that leaves the original in place violates it.

## Spike questions

1. Which macro kinds can be activated faithfully, per Rails version?
   Candidates: scope lambdas (replace via redefinition), lambda bodies of
   `if:`/`unless:` (replace the callback chain entry), validation options
   (reset `_validators` and the callback chain for that attribute, then
   re-apply).
2. Is a narrower target enough: mutate only **lambda/proc bodies passed to
   macros** (they are code, like a method body) and leave literal options
   (`maximum: 50`) to a later step?
3. How are such subjects named and addressed (`User.scope(:active)`?
   `User@validates:name`?) without breaking `stableId` and the report
   schema?
4. How does `MutantIdentity`/verdict reuse fingerprint them (ADR-11)?
5. What do `mutant` and other frameworks do? (Believed: `mutant` also only
   mutates method subjects — verify before claiming a lead.)

## Requirements (after the spike)

- Opt-in first (e.g. `mutation.rails_macros: true` or a separate subject
  kind), so existing scores do not jump unexplained.
- Only activation strategies proven faithful are enabled; others are
  reported, not silently skipped.
- The oracle corpus gets Rails-macro cases with known kills and survivors;
  `rake oracle` shows no false kills/survivors for them.
- Rails-specific code lives in an integration-side adapter, not in the
  core subject model ("No Parallel Implementations": one activation
  mechanism per subject kind, no copy of the def path).

## Related

- `docs/architecture/adr/ADR-13-def-injection-in-lexical-nesting.md`
- `docs/architecture/adr/ADR-14-detected-verdicts-must-be-caused-by-the-mutation.md`
- `lib/henitai/subject_resolver.rb`
- `docs/backlog/2026-11-12-ruby-rails-version-support-matrix.md`
