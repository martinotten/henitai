# frozen_string_literal: true

module Henitai
  # Answers whether any configured source root has changed, which is what makes
  # a prior run's survivor verdicts unsafe to reuse.
  #
  # Two change sets are considered together: files dirty in the worktree, and
  # files committed since the run being reused. Test-only churn is deliberately
  # ignored — a spec edit invalidates nothing about a *mutant*, only about
  # whether it is still killed, which the survivor rerun is about to re-measure
  # anyway.
  #
  # Every failure mode answers `true`. A wrong `true` costs one extra rerun; a
  # wrong `false` silently reuses a stale verdict, which is the whole failure
  # this guard exists to prevent.
  class DirtySourceDetector
    def initialize(includes:, git_diff_analyzer:)
      @includes = includes
      @git_diff_analyzer = git_diff_analyzer
    end

    def dirty?(dirty_worktree_files, git_sha: nil)
      # A nil list means the worktree could not be read at all, not that it is
      # clean.
      return true if dirty_worktree_files.nil?

      all_changed = dirty_worktree_files + committed_changed_files(git_sha)
      all_changed.any? { |path| in_include_root?(normalize_path(path)) }
    rescue StandardError
      true
    end

    private

    def committed_changed_files(git_sha)
      return [] unless git_sha

      @git_diff_analyzer.changed_files(from: git_sha, to: "HEAD")
    end

    def include_roots
      @include_roots ||= Array(@includes).map { |path| normalize_path(path) }
    end

    # Prefix match on a path boundary, not a bare start_with?: "lib" must not
    # match "library/foo.rb".
    def in_include_root?(path)
      include_roots.any? { |root| path == root || path.start_with?("#{root}/") }
    end

    def normalize_path(path) = File.expand_path(path)
  end
end
