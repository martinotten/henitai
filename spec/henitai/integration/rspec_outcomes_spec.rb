# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Integration::RspecOutcomes do
  let(:outcomes) { Henitai::TestFileOutcomes.new }
  let(:example_result) { Struct.new(:metadata, :execution_result) }
  let(:status_result) { Struct.new(:status) }
  let(:notification) { Struct.new(:example) }
  let(:reporter) { instance_double(RSpec::Core::Reporter, register_listener: nil) }

  def example(file, status)
    example_result.new({ file_path: file }, status_result.new(status))
  end

  it "records a failed example's spec file as failed" do
    described_class.record(outcomes, example("spec/a_spec.rb", :failed))

    expect(outcomes.failed_files).to eq([File.expand_path("spec/a_spec.rb")])
  end

  it "records passed and pending examples as passed" do
    %i[passed pending].each { |status| described_class.record(outcomes, example("spec/b_spec.rb", status)) }

    expect(outcomes.outcomes).to eq(File.expand_path("spec/b_spec.rb") => "passed")
  end

  it "skips examples that never ran" do
    described_class.record(outcomes, example("spec/c_spec.rb", nil))

    expect(outcomes.outcomes).to be_empty
  end

  it "registers a listener that records each finished example" do
    listener = nil
    allow(reporter).to receive(:register_listener) { |registered, *| listener = registered }

    described_class.register(outcomes, reporter)
    listener.example_finished(notification.new(example("spec/d_spec.rb", :failed)))

    expect(outcomes.failed_files).to eq([File.expand_path("spec/d_spec.rb")])
  end

  it "registers the listener for finished examples only" do
    described_class.register(outcomes, reporter)

    expect(reporter).to have_received(:register_listener).with(anything, :example_finished)
  end
end
