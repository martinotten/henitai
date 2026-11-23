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

  describe "#flush" do
    def flushing_reporter(log, name, error: nil)
      Class.new do
        define_method(:progress) { |*, **| nil }
        define_method(:flush) do
          log << name
          raise error if error
        end
      end.new
    end

    it "flushes every reporter that can, even after one of them fails", :aggregate_failures do
      log = []
      composite = described_class.new([flushing_reporter(log, :a, error: IOError.new("disk full")),
                                       recording_reporter(log, :no_flush), flushing_reporter(log, :b)])

      expect { composite.flush }.to output(/could not flush progress.*disk full/).to_stderr
      expect(log).to eq(%i[a b])
    end
  end

  describe ".for" do
    def config(reporters:, checkpoint: true)
      Struct.new(:reporters, :checkpoint_enabled, :reports_dir, :checkpoint_every, :checkpoint_interval)
            .new(reporters, checkpoint, "reports", 200, 30.0)
    end

    it "adds the history checkpointer next to the other reporters" do
      checkpointer = instance_double(Henitai::HistoryCheckpointer)

      reporter = described_class.for(config: config(reporters: %w[terminal]), source_provider: ->(_f) { "" },
                                     full_run: true, history_checkpointer: checkpointer)

      expect(reporter).to be_a(described_class)
    end

    it "returns the history checkpointer alone when it is the only observer" do
      checkpointer = instance_double(Henitai::HistoryCheckpointer)

      expect(described_class.for(config: config(reporters: []), source_provider: ->(_f) { "" },
                                 full_run: true, history_checkpointer: checkpointer)).to be(checkpointer)
    end
  end

  it "does nothing when given no reporters" do
    composite = described_class.new([])

    expect { composite.progress(:mutant) }.not_to raise_error
  end
end
