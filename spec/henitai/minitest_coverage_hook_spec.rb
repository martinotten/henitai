# frozen_string_literal: true

require "spec_helper"
require "henitai/minitest_coverage_hook"

# Loader file with no describable class; mirrors the spec/infra convention.
# rubocop:disable RSpec/DescribeClass
RSpec.describe "Minitest coverage hook" do
  it "registers the henitai_coverage extension with Minitest" do
    expect(Minitest.extensions).to include("henitai_coverage")
  end

  it "adds a Henitai coverage reporter when the plugin initializes" do
    reporters = []
    aggregate = instance_double(Minitest::CompositeReporter, reporters:)
    allow(Minitest).to receive(:reporter).and_return(aggregate)

    Minitest.plugin_henitai_coverage_init({})

    expect(reporters).to contain_exactly(
      an_instance_of(Henitai::MinitestCoverageReporter)
    )
  end
end
# rubocop:enable RSpec/DescribeClass
