# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::CompositeProgressReporter do
  def recording_reporter(log, name)
    Class.new do
      define_method(:initialize) do
        @log = log
        @name = name
      end
      define_method(:progress) do |mutant, scenario_result: nil|
        @log << [@name, mutant, scenario_result]
      end
    end.new
  end

  it "fans a progress call out to every reporter in order" do
    log = []
    composite = described_class.new([recording_reporter(log, :a), recording_reporter(log, :b)])

    composite.progress(:mutant, scenario_result: :result)

    expect(log).to eq([%i[a mutant result], %i[b mutant result]])
  end

  it "ignores nil reporters" do
    log = []
    composite = described_class.new([nil, recording_reporter(log, :only), nil])

    composite.progress(:mutant)

    expect(log).to eq([[:only, :mutant, nil]])
  end

  it "does nothing when given no reporters" do
    composite = described_class.new([])

    expect { composite.progress(:mutant) }.not_to raise_error
  end
end
