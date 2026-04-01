# frozen_string_literal: true

require "spec_helper"

IntegrationSpy = Class.new do
  attr_reader :calls

  def initialize
    @calls = Hash.new(0)
  end

  def select_tests(subject)
    @calls[:select_tests] += 1
    @calls[:last_subject] = subject.expression
    ["spec/foo_spec.rb"]
  end

  def run_mutant(mutant:, test_files:, timeout:)
    @calls[:run_mutant] += 1
    @calls[:last_test_files] = test_files
    @calls[:last_timeout] = timeout
    mutant.status = :killed
  end
end

RSpec.describe Henitai::ExecutionEngine do
  def build_subject(expression)
    Struct.new(:expression).new(expression)
  end

  def build_mutant(status, expression)
    Struct.new(:status, :subject) do
      def pending?
        status == :pending
      end
    end.new(status, build_subject(expression))
  end

  def build_integration
    IntegrationSpy.new
  end

  it "runs only pending mutants" do
    pending = build_mutant(:pending, "Foo#bar")
    ignored = build_mutant(:ignored, "Foo#baz")
    integration = build_integration

    described_class.new.run([pending, ignored], integration, Struct.new(:timeout).new(12.5))

    expect(integration.calls.slice(:select_tests, :run_mutant)).to eq(
      select_tests: 1,
      run_mutant: 1
    )
  end

  it "updates pending mutant statuses from the integration result" do
    pending = build_mutant(:pending, "Foo#bar")
    ignored = build_mutant(:ignored, "Foo#baz")
    integration = build_integration

    result = described_class.new.run([pending, ignored], integration, Struct.new(:timeout).new(12.5))

    expect(result.map(&:status)).to eq(%i[killed ignored])
  end
end
