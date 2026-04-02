# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::CoverageBootstrapper do
  around do |example|
    original = ENV.fetch("HENITAI_SKIP_COVERAGE_VALIDATION", nil)
    ENV.delete("HENITAI_SKIP_COVERAGE_VALIDATION")
    example.run
  ensure
    if original.nil?
      ENV.delete("HENITAI_SKIP_COVERAGE_VALIDATION")
    else
      ENV["HENITAI_SKIP_COVERAGE_VALIDATION"] = original
    end
  end

  def build_config
    Struct.new(:reports_dir).new("reports")
  end

  it "raises when coverage is missing" do
    static_filter = instance_double(Henitai::StaticFilter)

    bootstrapper = described_class.new(static_filter:)

    allow(static_filter).to receive(:coverage_lines_for).and_return({})

    expect do
      bootstrapper.ensure!(
        source_files: [File.expand_path("lib/sample.rb")],
        config: build_config
      )
    end.to raise_error(
      Henitai::CoverageError,
      /run the configured test suite/i
    )
  end

  it "accepts coverage when the configured source files are covered" do
    static_filter = instance_double(Henitai::StaticFilter)

    bootstrapper = described_class.new(static_filter:)

    allow(static_filter).to receive(:coverage_lines_for).and_return(
      { File.expand_path("lib/sample.rb") => [2] }
    )

    expect do
      bootstrapper.ensure!(
        source_files: [File.expand_path("lib/sample.rb")],
        config: build_config
      )
    end.not_to raise_error
  end
end
