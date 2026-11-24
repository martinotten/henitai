# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::Integration::ChildReportStore do
  subject(:store) { described_class.new }

  it "reads back what it wrote" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "logs", "mutant.report.json")
      store.write(path, "outcome" => "tests_finished", "exit_code" => 1)

      expect(store.read(path)).to eq("outcome" => "tests_finished", "exit_code" => 1)
    end
  end

  it "reads nil when no report was written" do
    Dir.mktmpdir do |dir|
      expect(store.read(File.join(dir, "missing.report.json"))).to be_nil
    end
  end

  it "reads nil when the report is not valid JSON" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "broken.report.json")
      File.write(path, "{\"outcome\":")

      expect(store.read(path)).to be_nil
    end
  end

  it "clears a report left by an earlier attempt" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "mutant.report.json")
      store.write(path, "outcome" => "tests_finished", "exit_code" => 0)
      store.clear(path)

      expect(store.read(path)).to be_nil
    end
  end

  it "ignores writes, reads and clears without a path" do
    expect([store.write(nil, "outcome" => "x"), store.read(nil), store.clear(nil)]).to eq([nil, nil, nil])
  end

  describe "running-file marker" do
    it "reads back the file a child reported as running" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "mutant.report.json")
        store.write_running(path, "/project/spec/b_spec.rb")

        expect(store.read_running(path)).to eq("/project/spec/b_spec.rb")
      end
    end

    it "keeps the marker in a sibling file next to the report" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "mutant.report.json")
        store.write_running(path, "/project/spec/b_spec.rb")

        expect(File.read("#{path}.running")).to eq("/project/spec/b_spec.rb")
      end
    end

    it "reads nil when no test was reported as running" do
      Dir.mktmpdir do |dir|
        expect(store.read_running(File.join(dir, "mutant.report.json"))).to be_nil
      end
    end

    it "removes the marker together with the report on clear" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "mutant.report.json")
        store.write_running(path, "/project/spec/b_spec.rb")
        store.clear(path)

        expect(store.read_running(path)).to be_nil
      end
    end

    it "ignores marker writes and reads without a path" do
      expect([store.write_running(nil, "/a_spec.rb"), store.read_running(nil)]).to eq([nil, nil])
    end
  end
end
