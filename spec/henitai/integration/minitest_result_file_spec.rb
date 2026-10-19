# frozen_string_literal: true

require "spec_helper"
require "minitest"
require "henitai/integration/minitest_result_file"

# A test class defined in this file whose test method comes from another one.
module HenitaiMinitestResultFileSpec
  class BaseTest < Minitest::Test; end

  class SubTest < BaseTest; end
end

RSpec.describe Henitai::Integration::MinitestResultFile do
  let(:outcomes) { Henitai::TestFileOutcomes.new }

  def result(klass:, source_location:, passed: true)
    instance_double(
      Minitest::Result,
      klass: klass, source_location: source_location, passed?: passed, skipped?: false
    )
  end

  it "prefers the file that defines the test class over the test method's file" do
    shared = result(klass: "HenitaiMinitestResultFileSpec::SubTest", source_location: ["/app/test/shared.rb", 4])

    expect(described_class.for(shared)).to eq(__FILE__)
  end

  it "falls back to the test method's file for classes that cannot be resolved" do
    anonymous = result(klass: "#<Class:0x0001>", source_location: ["/app/test/a_test.rb", 4])

    expect(described_class.for(anonymous)).to eq("/app/test/a_test.rb")
  end

  it "falls back to the method's file for built-in classes without a source location" do
    builtin = result(klass: "String", source_location: ["/app/test/a_test.rb", 4])

    expect(described_class.for(builtin)).to eq("/app/test/a_test.rb")
  end

  it "returns nil when neither the class nor the method has a usable file" do
    expect(described_class.for(result(klass: "Missing::Test", source_location: ["unknown", 0]))).to be_nil
  end

  it "records a failing result under the test class's file" do
    failing = result(klass: "HenitaiMinitestResultFileSpec::SubTest", source_location: ["/app/test/shared.rb", 4],
                     passed: false)

    described_class.record(outcomes, failing)

    expect(outcomes.outcomes).to eq(__FILE__ => "failed")
  end

  it "does not flag a passing result without a file" do
    described_class.record(outcomes, result(klass: "Missing::Test", source_location: nil))

    expect(outcomes.unattributed_failures?).to be(false)
  end

  it "flags a failing result without a file as unattributed" do
    described_class.record(outcomes, result(klass: "Missing::Test", source_location: nil, passed: false))

    expect(outcomes.unattributed_failures?).to be(true)
  end
end
