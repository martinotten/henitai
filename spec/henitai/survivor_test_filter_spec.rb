# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::SurvivorTestFilter do
  def build_mutant(stable_id:)
    instance_double(Henitai::Mutant, stable_id:)
  end

  def diff_analyzer_for(changed_files, worktree_changed_files: [])
    analyzer = instance_double(Henitai::GitDiffAnalyzer)
    allow(analyzer).to receive(:changed_files).with(from: anything, to: "HEAD")
                                              .and_return(changed_files)
    allow(analyzer).to receive(:working_tree_changed_files).and_return(worktree_changed_files)
    analyzer
  end

  def filter(coverage_map:, git_sha:, changed_files: [], worktree_changed_files: [], dirty_source_files: false)
    described_class.new(
      coverage_map:,
      git_sha:,
      dirty_source_files:,
      worktree_changed_files:,
      diff_analyzer: diff_analyzer_for(changed_files, worktree_changed_files:)
    )
  end

  it "marks mutants as stable when no covering tests changed" do
    mutant = build_mutant(stable_id: "abc")
    result = filter(
      coverage_map: { "abc" => ["spec/foo_spec.rb"] },
      git_sha: "deadbeef",
      changed_files: []
    ).apply([mutant])

    expect(result).to eq(stable: [mutant], pending: [])
  end

  it "marks mutants as pending when a covering test file changed" do
    mutant = build_mutant(stable_id: "abc")
    result = filter(
      coverage_map: { "abc" => ["spec/foo_spec.rb"] },
      git_sha: "deadbeef",
      changed_files: ["spec/foo_spec.rb"]
    ).apply([mutant])

    expect(result).to eq(stable: [], pending: [mutant])
  end

  it "marks mutants as pending when a covering test file is dirty in the worktree" do
    mutant = build_mutant(stable_id: "abc")
    result = filter(
      coverage_map: { "abc" => ["spec/foo_spec.rb"] },
      git_sha: "deadbeef",
      changed_files: [],
      worktree_changed_files: ["spec/foo_spec.rb"]
    ).apply([mutant])

    expect(result).to eq(stable: [], pending: [mutant])
  end

  it "marks mutant as pending when only one of multiple covering tests changed" do
    mutant = build_mutant(stable_id: "abc")
    result = filter(
      coverage_map: { "abc" => ["spec/foo_spec.rb", "spec/bar_spec.rb"] },
      git_sha: "deadbeef",
      changed_files: ["spec/bar_spec.rb"]
    ).apply([mutant])

    expect(result).to eq(stable: [], pending: [mutant])
  end

  it "marks all mutants as pending when a source file is dirty in the worktree" do
    mutant = build_mutant(stable_id: "abc")
    result = filter(
      coverage_map: { "abc" => ["spec/foo_spec.rb"] },
      git_sha: "deadbeef",
      changed_files: [],
      worktree_changed_files: ["lib/sample.rb"],
      dirty_source_files: true
    ).apply([mutant])

    expect(result).to eq(stable: [], pending: [mutant])
  end

  it "treats all mutants as pending when git_sha is nil" do
    mutant = build_mutant(stable_id: "abc")
    filter_instance = described_class.new(
      coverage_map: { "abc" => ["spec/foo_spec.rb"] },
      git_sha: nil,
      diff_analyzer: instance_double(Henitai::GitDiffAnalyzer)
    )
    result = filter_instance.apply([mutant])

    expect(result).to eq(stable: [], pending: [mutant])
  end

  it "treats mutants with no coverage data as pending" do
    mutant = build_mutant(stable_id: "abc")
    result = filter(
      coverage_map: {},
      git_sha: "deadbeef",
      changed_files: []
    ).apply([mutant])

    expect(result).to eq(stable: [], pending: [mutant])
  end

  it "treats mutants with empty coveredBy as pending" do
    mutant = build_mutant(stable_id: "abc")
    result = filter(
      coverage_map: { "abc" => [] },
      git_sha: "deadbeef",
      changed_files: []
    ).apply([mutant])

    expect(result).to eq(stable: [], pending: [mutant])
  end

  it "splits a mixed set correctly" do
    stable_mutant  = build_mutant(stable_id: "aaa")
    pending_mutant = build_mutant(stable_id: "bbb")

    result = filter(
      coverage_map: {
        "aaa" => ["spec/unchanged_spec.rb"],
        "bbb" => ["spec/changed_spec.rb"]
      },
      git_sha: "deadbeef",
      changed_files: ["spec/changed_spec.rb"]
    ).apply([stable_mutant, pending_mutant])

    expect(result).to eq(stable: [stable_mutant], pending: [pending_mutant])
  end

  it "treats all mutants as pending when the git diff raises" do
    mutant   = build_mutant(stable_id: "abc")
    analyzer = instance_double(Henitai::GitDiffAnalyzer)
    allow(analyzer).to receive(:changed_files).and_raise(Henitai::GitDiffError, "fatal")

    result = described_class.new(
      coverage_map: { "abc" => ["spec/foo_spec.rb"] },
      git_sha: "deadbeef",
      diff_analyzer: analyzer
    ).apply([mutant])

    expect(result).to eq(stable: [], pending: [mutant])
  end

  it "returns empty stable and pending for an empty mutant list" do
    result = filter(coverage_map: {}, git_sha: "abc", changed_files: []).apply([])
    expect(result).to eq(stable: [], pending: [])
  end
end
