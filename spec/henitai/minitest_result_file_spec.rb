# frozen_string_literal: true

require "spec_helper"
require "minitest"
require "henitai/minitest_result_file"

# A test class defined in this file whose test method comes from another one.
module HenitaiMinitestResultFileSpec
  class BaseTest < Minitest::Test
    def test_inherited; end
  end

  module SharedTests
    def test_shared; end
  end

  class SubTest < BaseTest
    include SharedTests
  end

  # Defined here and reopened elsewhere: the test method lives in another file.
  class ReopenedTest < Minitest::Test; end
  ReopenedTest.class_eval("def test_added; end", "/app/test/b_test.rb", 1) # rubocop:disable Style/EvalWithLocation
end

RSpec.describe Henitai::MinitestResultFile do
  let(:outcomes) { Henitai::TestFileOutcomes.new }

  def result(klass:, source_location:, name: "test_it", passed: true)
    instance_double(
      Minitest::Result,
      klass: klass, name: name, source_location: source_location, passed?: passed, skipped?: false
    )
  end

  it "uses the test class's file for a method inherited from a shared base class" do
    shared = result(klass: "HenitaiMinitestResultFileSpec::SubTest", name: "test_inherited",
                    source_location: ["/app/test/shared.rb", 4])

    expect(described_class.for(shared)).to eq(__FILE__)
  end

  it "uses the test class's file for a method from an included shared module" do
    shared = result(klass: "HenitaiMinitestResultFileSpec::SubTest", name: "test_shared",
                    source_location: ["/app/test/shared.rb", 4])

    expect(described_class.for(shared)).to eq(__FILE__)
  end

  it "uses the method's file for a test defined directly on a reopened class" do
    added = result(klass: "HenitaiMinitestResultFileSpec::ReopenedTest", name: "test_added",
                   source_location: ["/app/test/b_test.rb", 1])

    expect(described_class.for(added)).to eq("/app/test/b_test.rb")
  end

  it "uses the class's file when the method name no longer resolves on the class" do
    gone = result(klass: "HenitaiMinitestResultFileSpec::SubTest", name: "test_missing",
                  source_location: ["/app/test/shared.rb", 4])

    expect(described_class.for(gone)).to eq(__FILE__)
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

  it "names the file that defines a class, and nothing for an unknown name" do
    expect([described_class.class_file_of("HenitaiMinitestResultFileSpec::SubTest"),
            described_class.class_file_of("Missing::Test"),
            described_class.class_file_of("#<Class:0x0001>")]).to eq([__FILE__, nil, nil])
  end

  it "records a failing result under the test class's file" do
    failing = result(klass: "HenitaiMinitestResultFileSpec::SubTest", name: "test_inherited",
                     source_location: ["/app/test/shared.rb", 4], passed: false)

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
