# frozen_string_literal: true

require "json"
require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::SurvivorLoader do
  def write_report(dir, data)
    path = File.join(dir, "mutation-report.json")
    File.write(path, JSON.generate(data))
    path
  end

  def build_report(mutants:, file: "lib/sample.rb")
    {
      "schemaVersion" => "1.0",
      "files" => {
        file => {
          "language" => "ruby",
          "source" => "",
          "mutants" => mutants
        }
      }
    }
  end

  it "returns stable IDs of survived mutants" do
    Dir.mktmpdir do |dir|
      path = write_report(dir, build_report(mutants: [
                                              { "stableId" => "abc123", "status" => "Survived" },
                                              { "stableId" => "def456", "status" => "Killed" },
                                              { "stableId" => "ghi789", "status" => "Survived" }
                                            ]))
      expect(described_class.new(path).load).to contain_exactly("abc123", "ghi789")
    end
  end

  it "returns an empty array when no survivors exist" do
    Dir.mktmpdir do |dir|
      path = write_report(dir, build_report(mutants: [
                                              { "stableId" => "abc123", "status" => "Killed" }
                                            ]))
      expect(described_class.new(path).load).to be_empty
    end
  end

  it "raises FileNotFoundError when the file does not exist" do
    expect { described_class.new("/no/such/file.json").load }
      .to raise_error(Henitai::SurvivorLoader::FileNotFoundError, %r{no/such/file\.json})
  end

  it "raises InvalidReportError when the JSON is malformed" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "bad.json")
      File.write(path, "not json")
      expect { described_class.new(path).load }
        .to raise_error(Henitai::SurvivorLoader::InvalidReportError)
    end
  end

  it "skips mutant entries that lack stableId and warns" do
    Dir.mktmpdir do |dir|
      path = write_report(dir, build_report(mutants: [
                                              { "status" => "Survived" }
                                            ]))
      expect { described_class.new(path).load }.to output(/missing stableId/).to_stderr
    end
  end

  it "raises ScopeMismatchError when schemaVersion is absent" do
    Dir.mktmpdir do |dir|
      path = write_report(dir, { "files" => {} })
      expect { described_class.new(path).load }
        .to raise_error(Henitai::SurvivorLoader::ScopeMismatchError, /schemaVersion/)
    end
  end

  it "raises ScopeMismatchError when no file keys overlap with include_paths" do
    Dir.mktmpdir do |dir|
      path = write_report(dir, build_report(file: "other_project/lib/foo.rb", mutants: []))
      expect { described_class.new(path, include_paths: ["lib"]).load }
        .to raise_error(Henitai::SurvivorLoader::ScopeMismatchError, /no file overlap/)
    end
  end

  it "does not raise ScopeMismatchError when include_paths is empty" do
    Dir.mktmpdir do |dir|
      path = write_report(dir, build_report(file: "other/lib/foo.rb", mutants: []))
      expect { described_class.new(path).load }.not_to raise_error
    end
  end
end
