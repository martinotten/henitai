# frozen_string_literal: true

require_relative "verdict_fingerprint"

module Henitai
  # Binds cached verdicts to the inputs that were executed (ADR-16 §4).
  #
  # Before Gate 1 parses anything, the run records size and mtime of every
  # source and test file it may parse, load or execute, and of every test
  # dependency file ({VerdictFingerprint.dependency_files}). A verdict may be
  # fingerprinted only while its files still match that record: hashing them
  # then hashes the content that was parsed, loaded and executed.
  #
  # Any change counts, including an edit that was later undone: editors and
  # git move the mtime forward, so a restored file still differs from the
  # record. A dependency file changing, appearing or disappearing invalidates
  # every verdict of the run for good, since a helper loaded once (for
  # example by the fork server) affects every mutant. A tool that rewrites a
  # file and also restores its mtime is not detected; ADR-16 accepts that.
  class ExecutionProvenance
    # Stands in until a run has captured its inputs: nothing is intact, so a
    # verdict recorded without a capture is never cached.
    UNCAPTURED = Class.new { def intact?(_paths) = false }.new.freeze

    def self.capture(paths, root: Dir.pwd)
      dependencies = VerdictFingerprint.dependency_files(root)
      stats = (Array(paths) + dependencies).to_h { |path| [File.expand_path(path), stat_of(path)] }
      new(stats:, dependencies:, root:)
    end

    def self.stat_of(path)
      stat = File.stat(path)
      [stat.size, stat.mtime.to_i, stat.mtime.nsec]
    rescue SystemCallError
      nil
    end

    def initialize(stats:, dependencies:, root:)
      @stats = stats
      @dependencies = dependencies
      @root = root
      @dependencies_drifted = false
    end

    # True when every path was captured and is unchanged, and no test
    # dependency changed since the capture.
    def intact?(paths)
      dependencies_intact? && Array(paths).all? { |path| unchanged?(File.expand_path(path.to_s)) }
    end

    private

    def dependencies_intact?
      return false if @dependencies_drifted

      intact = VerdictFingerprint.dependency_files(@root) == @dependencies &&
               @dependencies.all? { |path| unchanged?(File.expand_path(path)) }
      @dependencies_drifted = true unless intact
      intact
    end

    def unchanged?(path)
      recorded = @stats[path]
      !recorded.nil? && self.class.stat_of(path) == recorded
    end
  end
end
