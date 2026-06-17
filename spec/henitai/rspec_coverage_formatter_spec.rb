# frozen_string_literal: true

require "spec_helper"
require "henitai/rspec_coverage_formatter"

# Loader file with no describable class; mirrors the spec/infra convention.
# rubocop:disable RSpec/DescribeClass
RSpec.describe "RSpec coverage formatter registration" do
  it "registers the Henitai coverage formatter with RSpec" do
    registered = RSpec::Core::Formatters::Loader.formatters.keys

    expect(registered).to include(Henitai::CoverageFormatter)
  end

  it "subscribes the formatter to the example_finished and dump_summary events" do
    notifications = RSpec::Core::Formatters::Loader
                    .formatters
                    .fetch(Henitai::CoverageFormatter)

    expect(notifications).to contain_exactly(:example_finished, :dump_summary)
  end
end
# rubocop:enable RSpec/DescribeClass
