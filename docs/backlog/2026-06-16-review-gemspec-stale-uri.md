# Fix Stale gemspec source_code_uri and Version Doc Mismatches

Status: backlog
Date: 2026-06-16
Severity: High (low effort)
Source: 2026-06-16 structured review

## Summary

The gemspec links to the wrong release tag and the README states a Ruby version
the gemspec does not require. Low-effort, high-visibility correctness fixes that
ship to RubyGems.

## Problem

- `henitai.gemspec:33`: `source_code_uri` is hardcoded to
  `.../tree/v0.1.10` while `spec.version` is `0.2.0`. RubyGems visitors land on
  the wrong tag.
- `README.md:46` states "Requires Ruby 4.0.2+" but `henitai.gemspec:26` declares
  `required_ruby_version = ">= 4.0.0"`. `.ruby-version` pins `4.0.2` (dev
  toolchain), but the gem supports 4.0.0.

## Fix Plan

1. **Derive the URI from the version.** Replace the hardcoded tag with an
   interpolated value so it never goes stale:
   ```ruby
   "source_code_uri" => "#{spec.homepage}/tree/v#{Henitai::VERSION}",
   ```
2. **Reconcile the Ruby version.** Decide the supported floor. Either:
   - bump `required_ruby_version` to `>= 4.0.2` to match README + `.ruby-version`,
     or
   - change README to "Requires Ruby 4.0.0+".
   Recommend matching README to gemspec (`4.0.0+`) unless a 4.0.2 feature is
   actually used — confirm with a quick grep for 4.0.2-only APIs first.
3. **Add a release guard.** Add a line to the release checklist / `CHANGELOG`
   process: verify `source_code_uri`, README version, and `CHANGELOG` top entry
   all match `Henitai::VERSION` before `gem build`.

## Acceptance

- `source_code_uri` resolves to the current version tag automatically.
- README Ruby version matches `required_ruby_version`.
- `bundle exec rubocop` (gemspec cops) green.

## Related

- [[2026-06-16-review-doc-debt]]
