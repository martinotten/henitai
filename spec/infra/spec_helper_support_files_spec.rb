# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Spec helper support loading" do
  it "loads helper files from spec/support without loading support specs" do
    support_files = Dir[File.expand_path("../support/**/*.rb", __dir__)]

    loaded_files = support_files.reject { |path| path.end_with?("_spec.rb") }

    expect(
      {
        loaded_spec_files: loaded_files.select { |path| path.end_with?("_spec.rb") },
        skipped_support_specs: support_files - loaded_files
      }
    ).to include(
      loaded_spec_files: [],
      skipped_support_specs: include(
        a_string_ending_with("simplecov_quiet_formatter_spec.rb"),
        a_string_ending_with("warning_silencer_spec.rb")
      )
    )
  end
end
# rubocop:enable RSpec/DescribeClass
