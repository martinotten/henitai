# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::DirtySourceDetector do
  def build_detector(includes: ["lib"], analyzer: instance_double(Henitai::GitDiffAnalyzer))
    described_class.new(includes: includes, git_diff_analyzer: analyzer)
  end

  def analyzer_returning(committed)
    instance_double(Henitai::GitDiffAnalyzer).tap do |analyzer|
      allow(analyzer).to receive(:changed_files).with(from: anything, to: "HEAD").and_return(committed)
    end
  end

  # Paths are expanded against the working directory, so every example runs in
  # a scratch directory rather than the checkout.
  around do |example|
    Dir.mktmpdir { |dir| Dir.chdir(dir) { example.run } }
  end

  describe "committed changes" do
    it "is true when a committed source file inside includes changed since git_sha" do
      detector = build_detector(analyzer: analyzer_returning(["lib/henitai/foo.rb"]))

      expect(detector.dirty?([], git_sha: "abc123")).to be(true)
    end

    it "is false when only test files changed since git_sha" do
      detector = build_detector(analyzer: analyzer_returning(["spec/henitai/foo_spec.rb"]))

      expect(detector.dirty?([], git_sha: "abc123")).to be(false)
    end

    it "does not consult git at all when git_sha is nil" do
      analyzer = instance_double(Henitai::GitDiffAnalyzer)
      detector = build_detector(analyzer: analyzer)

      expect(detector.dirty?([], git_sha: nil)).to be(false)
    end
  end

  describe "worktree changes" do
    it "is true for a dirty worktree file inside includes" do
      detector = build_detector(analyzer: analyzer_returning([]))

      expect(detector.dirty?(["lib/henitai/foo.rb"], git_sha: "abc123")).to be(true)
    end

    it "is false for a dirty worktree file outside includes" do
      detector = build_detector(analyzer: analyzer_returning([]))

      expect(detector.dirty?(["docs/notes.md"], git_sha: "abc123")).to be(false)
    end

    # nil means the worktree could not be read, which is not the same as clean.
    it "is true when the worktree file list is nil, regardless of git_sha" do
      detector = build_detector

      expect(detector.dirty?(nil, git_sha: "abc123")).to be(true)
    end

    it "is true when the worktree file list is nil even with no git_sha" do
      detector = build_detector

      expect(detector.dirty?(nil, git_sha: nil)).to be(true)
    end
  end

  describe "include-root matching" do
    it "matches a path boundary, not a bare string prefix" do
      # "library/" must not be swallowed by the "lib" root.
      detector = build_detector(analyzer: analyzer_returning(["library/thing.rb"]))

      expect(detector.dirty?([], git_sha: "abc123")).to be(false)
    end

    it "matches an include root named exactly" do
      detector = build_detector(includes: ["lib/henitai/foo.rb"], analyzer: analyzer_returning(["lib/henitai/foo.rb"]))

      expect(detector.dirty?([], git_sha: "abc123")).to be(true)
    end

    it "considers every configured include root" do
      detector = build_detector(includes: %w[lib app], analyzer: analyzer_returning(["app/models/thing.rb"]))

      expect(detector.dirty?([], git_sha: "abc123")).to be(true)
    end

    it "is false when there are no include roots at all" do
      detector = build_detector(includes: nil, analyzer: analyzer_returning(["lib/henitai/foo.rb"]))

      expect(detector.dirty?([], git_sha: "abc123")).to be(false)
    end
  end

  # A wrong `true` costs one extra rerun; a wrong `false` silently reuses a
  # stale verdict. So every failure answers `true`.
  describe "conservative fallback" do
    it "is true when the git diff raises" do
      analyzer = instance_double(Henitai::GitDiffAnalyzer)
      allow(analyzer).to receive(:changed_files).and_raise(Henitai::GitDiffError, "fatal")
      detector = build_detector(analyzer: analyzer)

      expect(detector.dirty?([], git_sha: "abc123")).to be(true)
    end

    it "is true when a path cannot be expanded" do
      detector = build_detector(analyzer: analyzer_returning(["lib/foo.rb"]))
      allow(File).to receive(:expand_path).and_raise(ArgumentError, "invalid byte sequence")

      expect(detector.dirty?([], git_sha: "abc123")).to be(true)
    end
  end
end
