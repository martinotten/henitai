# frozen_string_literal: true

module Henitai
  # Drops test files matching any of the configured exclude globs.
  #
  # This keeps a mutant child from re-running tests that themselves spawn
  # henitai or forked subprocesses -- the CLI and process-scheduler specs, when
  # dogfooding henitai on itself -- which would otherwise multiply processes and
  # log noise.
  #
  # Takes the pattern list rather than a configuration object: exclusion is a
  # path-matching rule, and keeping it free of configuration lookup makes it
  # directly testable.
  class ExcludedTestFilter
    # @param patterns [Array<String>, nil] exclude globs; nil and [] both mean
    #   "exclude nothing"
    def initialize(patterns:)
      @patterns = Array(patterns)
    end

    # @param tests [Array<String>] candidate test paths
    # @return [Array<String>] paths not matched by any pattern
    def reject(tests)
      return tests if @patterns.empty?

      tests.reject { |path| excluded?(path) }
    end

    private

    # FNM_PATHNAME so a single `*` does not match across a directory separator.
    # Without it, an exclude as narrow as "spec/a/*_spec.rb" would swallow every
    # test below spec/a as well.
    def excluded?(path)
      candidate = File.expand_path(path)
      expanded_patterns.any? do |pattern|
        File.fnmatch?(pattern, candidate, File::FNM_PATHNAME)
      end
    end

    # Both sides are expanded so a relative pattern still matches an absolute
    # test path, and vice versa.
    def expanded_patterns
      @expanded_patterns ||= @patterns.map { |pattern| File.expand_path(pattern) }
    end
  end
end
