# frozen_string_literal: true

require "json"
require "fileutils"
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

  it "returns a Report with survivor_ids of survived mutants" do
    Dir.mktmpdir do |dir|
      path = write_report(dir, build_report(mutants: [
                                              { "stableId" => "abc123", "status" => "Survived" },
                                              { "stableId" => "def456", "status" => "Killed" },
                                              { "stableId" => "ghi789", "status" => "Survived" }
                                            ]))
      expect(described_class.new(path).load.survivor_ids).to contain_exactly("abc123", "ghi789")
    end
  end

  it "returns an empty survivor_ids array when no survivors exist" do
    Dir.mktmpdir do |dir|
      path = write_report(dir, build_report(mutants: [
                                              { "stableId" => "abc123", "status" => "Killed" }
                                            ]))
      expect(described_class.new(path).load.survivor_ids).to be_empty
    end
  end

  it "returns a Report with coverage_map populated from coveredBy" do
    Dir.mktmpdir do |dir|
      path = write_report(dir, build_report(mutants: [
                                              {
                                                "stableId" => "abc123",
                                                "status" => "Survived",
                                                "coveredBy" => ["spec/foo_spec.rb", "spec/bar_spec.rb"]
                                              },
                                              { "stableId" => "def456", "status" => "Killed",
                                                "coveredBy" => ["spec/other_spec.rb"] }
                                            ]))
      report = described_class.new(path).load
      expect(report.coverage_map).to eq(
        "abc123" => ["spec/foo_spec.rb", "spec/bar_spec.rb"],
        "def456" => ["spec/other_spec.rb"]
      )
    end
  end

  it "omits mutants without coveredBy from coverage_map" do
    Dir.mktmpdir do |dir|
      path = write_report(dir, build_report(mutants: [
                                              { "stableId" => "abc123", "status" => "Survived" }
                                            ]))
      expect(described_class.new(path).load.coverage_map).to be_empty
    end
  end

  it "returns the gitSha from the report" do
    Dir.mktmpdir do |dir|
      data = build_report(mutants: []).merge("gitSha" => "deadbeef1234")
      path = write_report(dir, data)
      expect(described_class.new(path).load.git_sha).to eq("deadbeef1234")
    end
  end

  it "returns nil git_sha when the report has no gitSha" do
    Dir.mktmpdir do |dir|
      path = write_report(dir, build_report(mutants: []))
      expect(described_class.new(path).load.git_sha).to be_nil
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

  it "skips entries lacking stableId and warns" do
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

  it "does not raise ScopeMismatchError when report file paths are absolute but include paths are relative" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p("lib")
        abs_file = File.expand_path(File.join("lib", "sample.rb"))
        path = write_report(dir, build_report(file: abs_file, mutants: []))

        expect { described_class.new(path, include_paths: ["lib"]).load }
          .not_to raise_error
      end
    end
  end

  it "does not raise ScopeMismatchError when report file paths are relative but include paths are absolute" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p("lib")
        abs_include = File.expand_path("lib")
        path = write_report(dir, build_report(file: "lib/sample.rb", mutants: []))

        expect { described_class.new(path, include_paths: [abs_include]).load }
          .not_to raise_error
      end
    end
  end

  it "does not raise ScopeMismatchError when include_paths is empty" do
    Dir.mktmpdir do |dir|
      path = write_report(dir, build_report(file: "other/lib/foo.rb", mutants: []))
      expect { described_class.new(path).load }.not_to raise_error
    end
  end

  it "ignores nil file entries when collecting mutants" do
    Dir.mktmpdir do |dir|
      path = write_report(
        dir,
        {
          "schemaVersion" => "1.0",
          "files" => {
            "lib/sample.rb" => nil
          }
        }
      )

      expect(described_class.new(path).load.survivor_ids).to eq([])
    end
  end
end
