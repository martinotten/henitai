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
end
