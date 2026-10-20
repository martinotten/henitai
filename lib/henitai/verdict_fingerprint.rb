# frozen_string_literal: true

require "digest"
require "find"
require "json"

require_relative "generated_artifacts"

module Henitai
  # Content fingerprints that decide whether a stored verdict is still
  # trustworthy: the subject's source (method body) and the covering test
  # files must both be byte-identical to what was recorded. Survived verdicts
  # additionally record the full-map covering-set membership (ADR-11). Both
  # verdict kinds carry the run's {ReuseContext} fingerprint (test
  # dependencies, verdict-relevant configuration, henitai version) and are
  # reusable only under an identical one. Any read failure yields nil / a
  # mismatch — conservative, never reuse on doubt; rows recorded without a
  # context are never reusable.
  module VerdictFingerprint
    # Files that influence test behavior but never appear in any covering
    # set: helpers, support code, fixtures/factories, lockfile and tool
    # config. One combined hash over all of them gates survivor reuse.
    DEPENDENCY_GLOBS = %w[
      spec/spec_helper.rb
      spec/rails_helper.rb
      spec/support/**/*
      spec/fixtures/**/*
      spec/factories/**/*
      test/test_helper.rb
      test/support/**/*
      test/fixtures/**/*
      test/factories/**/*
      Gemfile.lock
      .henitai.yml
      .rspec
    ].freeze

    module_function

    # SHA256 of the subject's source lines. nil when the subject has no
    # source range or the file cannot be read.
    def subject_source_hash(mutant)
      subject = mutant.subject
      return nil unless subject.respond_to?(:source_file) && subject.respond_to?(:source_range)

      range = subject.source_range
      return nil unless range

      lines = File.readlines(subject.source_file)
      Digest::SHA256.hexdigest(lines[(range.begin - 1)..(range.end - 1)].to_a.join)
    rescue SystemCallError, IOError
      nil
    end

    # JSON fingerprint of the covering test files: their sorted paths, a
    # combined content hash and the reuse context. nil when no tests are known,
    # any is unreadable, or there is no context to bind the verdict to.
    def tests_fingerprint(test_files, context_sha:)
      return nil if context_sha.nil?

      paths = Array(test_files).map(&:to_s).sort
      return nil if paths.empty?

      sha = combined_content_sha(paths)
      return nil unless sha

      JSON.generate("paths" => paths, "sha" => sha, "context" => context_sha)
    end

    # True when every recorded test file still exists with identical content
    # and the recorded reuse context equals the current one.
    def tests_fingerprint_current?(fingerprint_json, context_sha:)
      return false if fingerprint_json.nil? || context_sha.nil?

      fingerprint = JSON.parse(fingerprint_json)
      fingerprint.fetch("context") == context_sha &&
        combined_content_sha(fingerprint.fetch("paths")) == fingerprint.fetch("sha")
    rescue StandardError
      false
    end

    # Existing dependency files resolved against +root+, sorted. Shared by
    # the fingerprint below and by the coverage freshness watch — a stale
    # per-test map after a dependency edit would let the test selector omit
    # a newly covering test. Uses Find with pruning instead of Dir.glob so
    # generated subtrees (thousands of mutation-log files under fixture
    # projects) are never walked at all.
    def dependency_files(root = Dir.pwd)
      files = DEPENDENCY_GLOBS.flat_map do |pattern|
        base = File.join(root, pattern)
        pattern.include?("*") ? pruned_tree_files(File.dirname(base.sub("/**/*", "/x"))) : [base]
      end
      files.select { |path| File.file?(path) }.uniq.sort
    end

    def pruned_tree_files(dir)
      return [] unless File.directory?(dir)

      collected = [] # : Array[String]
      Find.find(dir) do |path|
        Find.prune if File.directory?(path) && GeneratedArtifacts.generated_dir?(path)
        collected << path if File.file?(path)
      end
      collected
    end

    # Run-level combined SHA over the dependency file set. Missing files are
    # simply excluded (not an error); a read failure yields nil — no reuse.
    def dependency_fingerprint(root = Dir.pwd) = combined_content_sha(dependency_files(root))

    # Fingerprint recorded for a Survived verdict: the sorted full-map
    # intersection set (paths + combined content sha) plus the reuse context.
    # nil when any input is unavailable — the verdict is then never reusable.
    def survivor_tests_fingerprint(test_files, context_sha:)
      tests_fingerprint(test_files, context_sha:)
    end

    # True when the recorded covering set still equals the live one in
    # membership AND content, and the reuse context is unchanged.
    # Any parse/read failure or missing field resolves to stale.
    def survivor_fingerprint_current?(fingerprint_json, live_paths:, context_sha:)
      return false if fingerprint_json.nil? || context_sha.nil?

      survivor_fingerprint_matches?(JSON.parse(fingerprint_json), live_paths, context_sha)
    rescue StandardError
      false
    end

    def survivor_fingerprint_matches?(fingerprint, live_paths, context_sha)
      recorded_paths = fingerprint.fetch("paths")
      return false if recorded_paths.empty?

      recorded_paths == Array(live_paths).map(&:to_s).sort &&
        fingerprint.fetch("context") == context_sha &&
        combined_content_sha(recorded_paths) == fingerprint.fetch("sha")
    end

    def combined_content_sha(paths)
      digest = Digest::SHA256.new
      paths.each do |path|
        content = File.read(path)
        digest.update(path.bytesize.to_s)
        digest.update(":")
        digest.update(path)
        digest.update(content.bytesize.to_s)
        digest.update(":")
        digest.update(content)
      end
      digest.hexdigest
    rescue StandardError
      nil
    end
  end
end
