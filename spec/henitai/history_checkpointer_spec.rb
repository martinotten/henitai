# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::HistoryCheckpointer do
  let(:warnings) { [] }
  let(:store) do
    store = instance_double(Henitai::MutantHistoryStore)
    allow(store).to receive(:checkpoint) { |mutants, **| mutants.size }
    store
  end

  def build_config(every: 2, interval: 30.0)
    Struct.new(:checkpoint_every, :checkpoint_interval).new(every, interval)
  end

  def checkpointer(config: build_config, clock: -> { 0.0 })
    described_class.new(history_store: store, config:, run_id: "run-1", version: "9.9.9", clock:,
                        warner: ->(message) { warnings << message })
  end

  it "writes a batch once checkpoint_every verdicts have arrived", :aggregate_failures do
    writer = checkpointer
    writer.progress(:a, scenario_result: nil)
    expect(store).not_to have_received(:checkpoint)

    writer.progress(:b, scenario_result: nil)

    expect(store).to have_received(:checkpoint).with(%i[a b], version: "9.9.9", run_id: "run-1")
  end

  it "writes a batch once checkpoint_interval seconds have passed" do
    times = [0.0, 31.0]
    writer = checkpointer(config: build_config(every: 100), clock: -> { times.shift || 31.0 })

    writer.progress(:a)

    expect(store).to have_received(:checkpoint).with([:a], version: "9.9.9", run_id: "run-1")
  end

  it "writes the pending verdicts on flush and counts what it committed", :aggregate_failures do
    writer = checkpointer(config: build_config(every: 100))
    writer.progress(:a)

    writer.flush
    writer.flush

    expect(store).to have_received(:checkpoint).once
    expect(writer.committed).to eq(1)
  end

  it "stops checkpointing after a failed write and warns once", :aggregate_failures do
    allow(store).to receive(:checkpoint).and_raise(SQLite3::BusyException, "database is locked")
    writer = checkpointer(config: build_config(every: 1))

    writer.progress(:a)
    writer.progress(:b)
    writer.flush

    expect(store).to have_received(:checkpoint).once
    expect(warnings.size).to eq(1)
    expect(warnings.first).to match(/could not checkpoint mutation history.*database is locked/)
    expect(writer.committed).to eq(0)
  end

  it "counts a committed batch even when a deferred signal arrives right after the write" do
    allow(store).to receive(:checkpoint) do |mutants, **|
      Process.kill(:TERM, Process.pid)
      sleep 0.05
      mutants.size
    end
    writer = checkpointer(config: build_config(every: 100))
    writer.progress(:a)
    resent = []
    allow(Henitai::SignalDeferral::RESEND).to receive(:call) { |signal| resent << signal }

    writer.flush

    expect([writer.committed, resent]).to eq([1, ["TERM"]])
  end
end
