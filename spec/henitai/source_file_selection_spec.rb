# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Henitai::SourceFileSelection do
  def build_config(includes: ["lib"], excludes: [])
    Struct.new(:includes, :excludes).new(includes, excludes)
  end

  def build_selection(config: build_config, since: nil, analyzer: nil, per_test_coverage: nil)
    described_class.new(
      config: config,
      since: since,
      git_diff_analyzer: analyzer || instance_double(Henitai::GitDiffAnalyzer),
      per_test_coverage: per_test_coverage || instance_double(Henitai::PerTestCoverage)
    )
  end

  def in_project(files, &block)
    Dir.mktmpdir do |dir|
      files.each do |path|
        FileUtils.mkdir_p(File.join(dir, File.dirname(path)))
        File.write(File.join(dir, path), "")
      end
      Dir.chdir(dir, &block)
    end
  end

  describe "#included_source_files" do
    it "globs .rb files recursively under every include root" do
      in_project(["lib/a.rb", "lib/nested/b.rb", "app/c.rb"]) do
        selection = build_selection(config: build_config(includes: %w[lib app]))

        expect(selection.included_source_files).to contain_exactly("lib/a.rb", "lib/nested/b.rb", "app/c.rb")
      end
    end

    it "ignores non-Ruby files" do
      in_project(["lib/a.rb", "lib/README.md"]) do
        expect(build_selection.included_source_files).to eq(["lib/a.rb"])
      end
    end

    it "de-duplicates a file reachable through two overlapping include roots" do
      in_project(["lib/nested/a.rb"]) do
        selection = build_selection(config: build_config(includes: %w[lib lib/nested]))

        expect(selection.included_source_files).to eq(["lib/nested/a.rb"])
      end
    end

    it "returns nothing when includes is nil" do
      in_project(["lib/a.rb"]) do
        expect(build_selection(config: build_config(includes: nil)).included_source_files).to eq([])
      end
    end
  end

  describe "#reject_excluded" do
    it "returns the files untouched, without expanding any path, when excludes is empty", :aggregate_failures do
      # The early return is what keeps a no-excludes run off the filesystem.
      selection = build_selection(config: build_config(excludes: []))
      allow(File).to receive(:expand_path).and_call_original

      expect(selection.reject_excluded(["lib/foo.rb"])).to eq(["lib/foo.rb"])
      expect(File).not_to have_received(:expand_path)
    end

    it "filters out files matched by an exclude glob" do
      in_project(["lib/foo.rb", "lib/exclude_me.rb"]) do
        selection = build_selection(config: build_config(excludes: ["lib/exclude*"]))

        expect(selection.reject_excluded(["lib/foo.rb", "lib/exclude_me.rb"])).to eq(["lib/foo.rb"])
      end
    end

    it "matches a relative candidate against an absolute exclude, and vice versa" do
      in_project(["lib/exclude_me.rb"]) do
        selection = build_selection(config: build_config(excludes: ["lib/exclude*"]))

        expect(selection.reject_excluded([File.expand_path("lib/exclude_me.rb")])).to eq([])
      end
    end

    it "keeps everything when the exclude glob matches no file on disk" do
      in_project(["lib/foo.rb"]) do
        selection = build_selection(config: build_config(excludes: ["lib/nothing*"]))

        expect(selection.reject_excluded(["lib/foo.rb"])).to eq(["lib/foo.rb"])
      end
    end
  end

  describe "#filter_changed" do
    it "returns the files untouched when no --since ref is set" do
      analyzer = instance_double(Henitai::GitDiffAnalyzer)
      selection = build_selection(since: nil, analyzer: analyzer)

      expect(selection.filter_changed(["lib/foo.rb"])).to eq(["lib/foo.rb"])
    end

    it "keeps only files that changed since the ref" do
      analyzer = instance_double(
        Henitai::GitDiffAnalyzer,
        changed_files: ["lib/changed.rb"], working_tree_changed_files: []
      )
      per_test = instance_double(Henitai::PerTestCoverage, source_files_covered_by: [])
      selection = build_selection(since: "main", analyzer: analyzer, per_test_coverage: per_test)

      expect(selection.filter_changed(["lib/changed.rb", "lib/untouched.rb"])).to eq(["lib/changed.rb"])
    end

    # The working tree is what actually gets tested, so a dirty file counts as
    # changed even with nothing committed.
    it "counts working-tree changes, not only committed ones" do
      analyzer = instance_double(
        Henitai::GitDiffAnalyzer,
        changed_files: [], working_tree_changed_files: ["lib/dirty.rb"]
      )
      per_test = instance_double(Henitai::PerTestCoverage, source_files_covered_by: [])
      selection = build_selection(since: "main", analyzer: analyzer, per_test_coverage: per_test)

      expect(selection.filter_changed(["lib/dirty.rb", "lib/clean.rb"])).to eq(["lib/dirty.rb"])
    end

    # An edited spec pulls in the sources it covers, so the mutants it could
    # kill get re-tested.
    it "pulls in source files covered by a changed test file" do
      analyzer = instance_double(
        Henitai::GitDiffAnalyzer,
        changed_files: ["spec/foo_spec.rb"], working_tree_changed_files: []
      )
      per_test = instance_double(Henitai::PerTestCoverage)
      allow(per_test).to receive(:source_files_covered_by).and_return([])
      allow(per_test).to receive(:source_files_covered_by)
        .with(File.expand_path("spec/foo_spec.rb")).and_return(["lib/foo.rb"])
      selection = build_selection(since: "main", analyzer: analyzer, per_test_coverage: per_test)

      expect(selection.filter_changed(["lib/foo.rb", "lib/other.rb"])).to eq(["lib/foo.rb"])
    end

    it "returns nothing when nothing changed" do
      analyzer = instance_double(
        Henitai::GitDiffAnalyzer, changed_files: [], working_tree_changed_files: []
      )
      per_test = instance_double(Henitai::PerTestCoverage, source_files_covered_by: [])
      selection = build_selection(since: "main", analyzer: analyzer, per_test_coverage: per_test)

      expect(selection.filter_changed(["lib/foo.rb"])).to eq([])
    end
  end

  describe "#call" do
    # An excluded file stays excluded even when it is the only thing that
    # changed — excludes are not a tiebreak, they are absolute. (Both stages are
    # filters over the same list, so they commute; the guarantee is that both
    # run, not that they run in this order.)
    it "applies excludes even when the excluded file is the only changed one" do
      in_project(["lib/foo.rb", "lib/exclude_me.rb"]) do
        analyzer = instance_double(
          Henitai::GitDiffAnalyzer,
          changed_files: ["lib/exclude_me.rb"], working_tree_changed_files: []
        )
        per_test = instance_double(Henitai::PerTestCoverage, source_files_covered_by: [])
        selection = build_selection(
          config: build_config(excludes: ["lib/exclude*"]),
          since: "main", analyzer: analyzer, per_test_coverage: per_test
        )

        expect(selection.call).to eq([])
      end
    end

    it "returns the included files when there are no excludes and no ref" do
      in_project(["lib/a.rb"]) do
        expect(build_selection.call).to eq(["lib/a.rb"])
      end
    end
  end
end
