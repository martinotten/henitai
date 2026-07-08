# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Integration::MinitestSuiteCommand do
  subject(:command) { described_class.new.build(test_files) }

  let(:test_files) { ["test/sample_test.rb", "test/other_test.rb"] }

  it "builds the bundle exec ruby argv with the minitest hooks required" do
    expect(command).to eq(
      [
        "bundle", "exec", "ruby", "-I", "test",
        "-r", "henitai/minitest_simplecov",
        "-r", "henitai/minitest_coverage_hook",
        "-e", "ARGV.each { |f| require File.expand_path(f) }",
        "test/sample_test.rb", "test/other_test.rb"
      ]
    )
  end

  context "when given no test files" do
    let(:test_files) { [] }

    it "still builds a runnable argv with the trailing require snippet last" do
      expect(command.last).to eq("ARGV.each { |f| require File.expand_path(f) }")
    end
  end
end
