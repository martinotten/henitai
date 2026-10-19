# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::TestFileOutcomes do
  subject(:outcomes) { described_class.new }

  it "reports a file as failed when any example in it failed" do
    outcomes.record("spec/a_spec.rb", failed: false)
    outcomes.record("spec/a_spec.rb", failed: true)

    expect(outcomes.failed_files).to eq([File.expand_path("spec/a_spec.rb")])
  end

  it "keeps passing files out of the failed list" do
    outcomes.record("spec/b_spec.rb", failed: false)

    expect(outcomes.failed_files).to be_empty
  end

  it "maps each expanded file path to passed or failed" do
    outcomes.record("spec/a_spec.rb", failed: false)
    outcomes.record("spec/b_spec.rb", failed: true)

    expect(outcomes.outcomes).to eq(
      File.expand_path("spec/a_spec.rb") => "passed",
      File.expand_path("spec/b_spec.rb") => "failed"
    )
  end

  it "round-trips through the report file" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, described_class::REPORT_FILE_NAME)
      outcomes.record("spec/c_spec.rb", failed: true)
      outcomes.write(path)

      expect(described_class.load(path).outcomes).to eq(outcomes.outcomes)
    end
  end

  it "loads an empty outcome map when the report file is missing" do
    Dir.mktmpdir do |dir|
      expect(described_class.load(File.join(dir, "missing.json")).outcomes).to eq({})
    end
  end

  it "resolves the report path inside the given reports directory" do
    expect(described_class.report_path("reports")).to eq(File.join("reports", "henitai_suite_outcomes.json"))
  end

  it "has no unattributed failures by default" do
    expect(outcomes.unattributed_failures?).to be(false)
  end

  it "round-trips an unattributed failure through the report file" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, described_class::REPORT_FILE_NAME)
      outcomes.record_unattributed_failure
      outcomes.write(path)

      expect(described_class.load(path).unattributed_failures?).to be(true)
    end
  end

  it "omits the unattributed marker from reports of clean runs" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, described_class::REPORT_FILE_NAME)
      outcomes.write(path)

      expect(JSON.parse(File.read(path))).to eq("outcomes" => {})
    end
  end
end
