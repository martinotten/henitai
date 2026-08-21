# frozen_string_literal: true

module Henitai
  # Resolves which source files a run mutates: everything under `includes:`,
  # minus anything matched by `excludes:`, optionally narrowed to what changed
  # since a git ref.
  #
  # Excludes are absolute, not a tiebreak: an excluded file (a standalone entry
  # point that cannot be mutation-tested in-process, say) stays excluded even
  # when it is the only thing that changed. Both stages are filters over the
  # same list, so they commute — excludes run first only to keep the
  # per-test-coverage lookups in `filter_changed` off files that are already
  # out of scope.
  class SourceFileSelection
    def initialize(config:, since:, git_diff_analyzer:, per_test_coverage:)
      @config = config
      @since = since
      @git_diff_analyzer = git_diff_analyzer
      @per_test_coverage = per_test_coverage
    end

    def call
      filter_changed(reject_excluded(included_source_files))
    end

    def included_source_files
      Array(@config.includes).flat_map do |include_path|
        Dir.glob(File.join(include_path, "**", "*.rb"))
      end.uniq
    end

    # Drops files matched by any `excludes:` glob. Compared as expanded paths so
    # a relative glob and an absolute candidate still match.
    def reject_excluded(files)
      excluded = excluded_source_files
      return files if excluded.empty?

      files.reject { |path| excluded.include?(normalize_path(path)) }
    end

    def filter_changed(files)
      return files unless @since

      changed = changed_paths_since.map { |path| normalize_path(path) }
      changed += covered_sources_for_changed_tests(changed)
      files.select { |path| changed.include?(normalize_path(path)) }
    end

    private

    def excluded_source_files
      Array(@config.excludes)
        .flat_map { |pattern| Dir.glob(pattern) }
        .map { |path| normalize_path(path) }
    end

    # Committed changes since the ref plus the current working tree (tracked
    # dirty and untracked files): the working tree is what gets tested, so it is
    # always part of "changed since REF".
    def changed_paths_since
      @git_diff_analyzer.changed_files(from: @since, to: "HEAD") +
        @git_diff_analyzer.working_tree_changed_files
    end

    # Changed test files select the source files they cover, so an edited test
    # re-tests the subjects it can kill. Uses the per-test map from the previous
    # run — Gate 1 runs before this run's bootstrap finishes.
    def covered_sources_for_changed_tests(changed_paths)
      changed_paths
        .flat_map { |path| @per_test_coverage.source_files_covered_by(path) }
        .map { |path| normalize_path(path) }
    end

    def normalize_path(path) = File.expand_path(path)
  end
end
