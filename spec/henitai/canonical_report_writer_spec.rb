# frozen_string_literal: true

require "fileutils"
require "json"
require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::CanonicalReportWriter do
  def schema(files)
    { "schemaVersion" => "1.0", "files" => files }
  end

  it "writes the schema verbatim on an authoritative write" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "nested", "mutation-report.json")

      described_class.write(schema({ "a.rb" => { "mutants" => [] } }), path:, authoritative: true)

      expect(JSON.parse(File.read(path))).to eq(schema({ "a.rb" => { "mutants" => [] } }))
    end
  end

  it "creates the parent directory when it does not exist" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "a", "b", "mutation-report.json")

      described_class.write(schema({}), path:, authoritative: true)

      expect(File).to exist(path)
    end
  end

  it "merges into the existing report on a non-authoritative write", :aggregate_failures do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        path = File.join(dir, "mutation-report.json")
        File.write("kept.rb", "# still here\n")
        File.write("new.rb", "# still here\n")
        File.write(path, JSON.pretty_generate(schema({ "kept.rb" => {
                                                       "mutants" => [{ "stableId" => "k1" }]
                                                     } })))

        described_class.write(
          schema({ "new.rb" => { "mutants" => [{ "stableId" => "n1" }] } }),
          path:, authoritative: false
        )

        expect(JSON.parse(File.read(path))["files"].keys).to contain_exactly("kept.rb", "new.rb")
      end
    end
  end

  it "prunes a prior entry whose source file is gone on a non-authoritative write" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        path = File.join(dir, "mutation-report.json")
        File.write("new.rb", "# still here\n")
        File.write(path, JSON.pretty_generate(schema({ "deleted.rb" => {
                                                       "mutants" => [{ "stableId" => "d1" }]
                                                     } })))

        described_class.write(
          schema({ "new.rb" => { "mutants" => [{ "stableId" => "n1" }] } }),
          path:, authoritative: false
        )

        expect(JSON.parse(File.read(path))["files"].keys).to contain_exactly("new.rb")
      end
    end
  end
end
