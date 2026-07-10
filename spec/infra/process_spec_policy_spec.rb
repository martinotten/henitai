# frozen_string_literal: true

require "yaml"
require "spec_helper"

# Process-boundary specs run in normal CI but are excluded from mutant children.
# rubocop:disable RSpec/DescribeClass
RSpec.describe "Process spec policy" do
  it "excludes only process-boundary specs from self-mutation runs" do
    config = YAML.safe_load_file(File.expand_path("../../.henitai.yml", __dir__))

    expect(config.fetch("test_excludes")).to eq(["spec/**/*_process_spec.rb"])
  end
end
# rubocop:enable RSpec/DescribeClass
