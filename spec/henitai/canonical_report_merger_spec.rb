# frozen_string_literal: true

require "fileutils"
require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::CanonicalReportMerger do
  def mutant_schema(stable_id, status: "Killed")
    { id: stable_id, stableId: stable_id, mutatorName: "EqualityOperator", replacement: "!=",
      location: { start: { line: 1, column: 1 }, end: { line: 1, column: 1 } }, status:,
      description: "desc" }
  end

  def file_entry(*mutants)
    { language: "ruby", source: "", mutants: }
  end

  def schema(files, **extra)
    { schemaVersion: "1.0", sessionId: "session", thresholds: { high: 80, low: 60 }, files:, **extra }
  end

  def write_prior(data)
    path = "mutation-report.json"
    File.write(path, JSON.pretty_generate(data))
    path
  end

  around do |example|
    Dir.mktmpdir { |dir| Dir.chdir(dir) { example.run } }
  end

  describe ".merge" do
    it "returns the current schema unchanged when no prior report exists" do
      current = schema({ "a.rb" => file_entry(mutant_schema("a1")) })

      merged = described_class.merge(current, "mutation-report.json")

      expect(merged).to eq(JSON.parse(JSON.generate(current)))
    end

    it "does not read a prior report that does not exist" do
      current = schema({ "a.rb" => file_entry(mutant_schema("a1")) })
      allow(File).to receive(:read).and_call_original

      described_class.merge(current, "mutation-report.json")

      expect(File).not_to have_received(:read)
    end

    it "keeps a prior file's mutants when a scoped run only touches another file", :aggregate_failures do
      prior_path = write_prior(schema({
                                        "x.rb" => file_entry(mutant_schema("x1")),
                                        "y.rb" => file_entry(mutant_schema("y1", status: "Survived"))
                                      }))
      current = schema({ "y.rb" => file_entry(mutant_schema("y1", status: "Killed")) })

      merged = described_class.merge(current, prior_path)

      expect(merged["files"].keys).to contain_exactly("x.rb", "y.rb")
      expect(merged["files"]["x.rb"]["mutants"]).to eq(
        [mutant_schema("x1")].map { |m| JSON.parse(JSON.generate(m)) }
      )
      expect(merged["files"]["y.rb"]["mutants"].first["status"]).to eq("Killed")
    end

    it "still reflects only the current run's files (merge does not preserve staleness on its own)" do
      prior_path = write_prior(schema({ "y.rb" => file_entry(mutant_schema("y1")) }))
      current = schema({ "x.rb" => file_entry(mutant_schema("x1")) })

      merged = described_class.merge(current, prior_path)

      expect(merged["files"].keys).to contain_exactly("x.rb", "y.rb")
    end

    it "overlays a previously-survived mutant with its rerun verdict without losing siblings" do
      prior_path = write_prior(schema({
                                        "x.rb" => file_entry(
                                          mutant_schema("k1", status: "Killed"),
                                          mutant_schema("s1", status: "Survived")
                                        )
                                      }))
      current = schema({ "x.rb" => file_entry(mutant_schema("s1", status: "Killed")) })

      merged = described_class.merge(current, prior_path)
      statuses = merged["files"]["x.rb"]["mutants"].to_h { |m| [m["stableId"], m["status"]] }

      expect(statuses).to eq("k1" => "Killed", "s1" => "Killed")
    end

    it "lets the current run's mutant win when the same stableId appears in both" do
      prior_path = write_prior(schema({ "x.rb" => file_entry(mutant_schema("x1", status: "Survived")) }))
      current = schema({ "x.rb" => file_entry(mutant_schema("x1", status: "Killed")) })

      merged = described_class.merge(current, prior_path)

      expect(merged["files"]["x.rb"]["mutants"]).to eq(
        [JSON.parse(JSON.generate(mutant_schema("x1", status: "Killed")))]
      )
    end

    it "replaces a prior mutant identified by the current mutant's legacy stable id" do
      prior_path = write_prior(schema({ "x.rb" => file_entry(mutant_schema("legacy-x1", status: "Survived")) }))
      replacement = mutant_schema("x1", status: "Killed").merge(legacyStableId: "legacy-x1")
      current = schema({ "x.rb" => file_entry(replacement) })

      merged = described_class.merge(current, prior_path)

      expect(merged["files"]["x.rb"]["mutants"]).to eq([JSON.parse(JSON.generate(replacement))])
    end

    it "drops a file left with zero mutants after its only mutant is overlaid elsewhere" do
      prior_path = write_prior(schema({ "x.rb" => file_entry(mutant_schema("x1")) }))
      current = schema({ "moved.rb" => file_entry(mutant_schema("x1")) })

      merged = described_class.merge(current, prior_path)

      expect(merged["files"].keys).to contain_exactly("moved.rb")
    end

    it "takes the current run's top-level singletons, not the prior's" do
      prior_path = write_prior(schema({ "x.rb" => file_entry(mutant_schema("x1")) }, sessionId: "old"))
      current = schema({ "x.rb" => file_entry(mutant_schema("x1")) }, sessionId: "new")

      merged = described_class.merge(current, prior_path)

      expect(merged["sessionId"]).to eq("new")
    end

    it "falls back to the current schema alone when the prior file is corrupt" do
      File.write("mutation-report.json", "not json")
      current = schema({ "x.rb" => file_entry(mutant_schema("x1")) })

      merged = described_class.merge(current, "mutation-report.json")

      expect(merged).to eq(JSON.parse(JSON.generate(current)))
    end

    it "falls back to the current schema alone when the prior file has no files key" do
      prior_path = write_prior({ "schemaVersion" => "1.0" })
      current = schema({ "x.rb" => file_entry(mutant_schema("x1")) })

      merged = described_class.merge(current, prior_path)

      expect(merged).to eq(JSON.parse(JSON.generate(current)))
    end

    it "is idempotent when merging the same current schema twice in a row" do
      prior_path = write_prior(schema({ "x.rb" => file_entry(mutant_schema("x1")) }))
      current = schema({ "y.rb" => file_entry(mutant_schema("y1")) })

      first = described_class.merge(current, prior_path)
      write_prior(first)
      second = described_class.merge(current, prior_path)

      expect(second).to eq(first)
    end

    it "falls back to the current run alone if a merge would end up thinner than it" do
      prior_path = write_prior(schema({ "x.rb" => file_entry(mutant_schema("x1")) }))
      current = schema({ "x.rb" => file_entry(mutant_schema("x1"), mutant_schema("x2")) })
      allow(described_class).to receive(:merge_files).and_return(current.merge("files" => {}))

      merged = described_class.merge(current, prior_path)

      expect(merged["files"]["x.rb"]["mutants"].size).to eq(2)
    end

    it "produces string-keyed output that round-trips through JSON", :aggregate_failures do
      prior_path = write_prior(schema({ "x.rb" => file_entry(mutant_schema("x1")) }))
      current = schema({ "y.rb" => file_entry(mutant_schema("y1")) })

      merged = described_class.merge(current, prior_path)

      expect(JSON.parse(JSON.generate(merged))).to eq(merged)
      expect(merged.keys).to all(be_a(String))
    end

    it "keeps an unchanged prior report when a --since run has no changed files" do
      prior_path = write_prior(schema({ "x.rb" => file_entry(mutant_schema("x1")) }))
      current = schema({})

      merged = described_class.merge(current, prior_path)

      expect(merged["files"]).to eq(
        JSON.parse(JSON.generate(schema({ "x.rb" => file_entry(mutant_schema("x1")) }))).fetch("files")
      )
    end
  end

  describe ".merge with prune_missing: true" do
    it "drops a prior file entry whose source file no longer exists on disk" do
      prior_path = write_prior(schema({
                                        "gone.rb" => file_entry(mutant_schema("g1")),
                                        "kept.rb" => file_entry(mutant_schema("k1"))
                                      }))
      File.write("kept.rb", "# still here\n")
      current = schema({ "other.rb" => file_entry(mutant_schema("o1")) })
      File.write("other.rb", "# current run\n")

      merged = described_class.merge(current, prior_path, prune_missing: true)

      expect(merged["files"].keys).to contain_exactly("kept.rb", "other.rb")
    end

    it "keeps a missing prior file entry when pruning is off (default)" do
      prior_path = write_prior(schema({ "gone.rb" => file_entry(mutant_schema("g1")) }))
      current = schema({ "other.rb" => file_entry(mutant_schema("o1")) })

      merged = described_class.merge(current, prior_path)

      expect(merged["files"].keys).to contain_exactly("gone.rb", "other.rb")
    end
  end
end
