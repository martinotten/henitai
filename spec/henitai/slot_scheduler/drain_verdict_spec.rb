# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::SlotScheduler::DrainVerdict do
  subject(:verdict) { described_class.new(integration: integration) }

  let(:integration) { instance_double(Henitai::Integration::Rspec) }
  let(:log_paths) { { log_path: "/dev/null" } }

  def build_slot(forced_outcome:, term_sent_at: nil)
    Henitai::SlotScheduler::Slot.new(
      1, nil, 12, 0.0, 5.0, log_paths, 0, true, term_sent_at, forced_outcome, 0
    )
  end

  it "uses the real exit status when it exited before any signal was sent" do
    status = instance_double(Process::Status, exited?: true)
    slot = build_slot(forced_outcome: :timeout)
    allow(integration).to receive(:build_result).with(status, log_paths).and_return(:real)

    expect(verdict.build(slot, status)).to eq(:real)
  end

  # The load-bearing rule: a child that traps SIGTERM and exits 0 would
  # otherwise be recorded as :survived, turning a timeout into a false
  # survivor.
  it "uses the forced outcome when a signal was already sent, even if the status exited" do
    status = instance_double(Process::Status, exited?: true)
    slot = build_slot(forced_outcome: :interrupted, term_sent_at: 1.0)
    allow(integration).to receive(:build_result).with(:interrupted, log_paths).and_return(:forced)

    expect(verdict.build(slot, status)).to eq(:forced)
  end

  it "uses the forced outcome when the status did not exit" do
    status = instance_double(Process::Status, exited?: false)
    slot = build_slot(forced_outcome: :interrupted)
    allow(integration).to receive(:build_result).with(:interrupted, log_paths).and_return(:forced)

    expect(verdict.build(slot, status)).to eq(:forced)
  end

  it "uses the forced outcome when there is no status at all" do
    slot = build_slot(forced_outcome: :timeout)
    allow(integration).to receive(:build_result).with(:timeout, log_paths).and_return(:forced)

    expect(verdict.build(slot, nil)).to eq(:forced)
  end

  it "falls back to :timeout when the status did not exit and forced_outcome is nil" do
    status = instance_double(Process::Status, exited?: false)
    slot = build_slot(forced_outcome: nil)
    allow(integration).to receive(:build_result).with(:timeout, log_paths).and_return(:fallback)

    expect(verdict.build(slot, status)).to eq(:fallback)
  end

  it "falls back to :timeout when there is neither a status nor a forced outcome" do
    slot = build_slot(forced_outcome: nil)
    allow(integration).to receive(:build_result).with(:timeout, log_paths).and_return(:fallback)

    expect(verdict.build(slot, nil)).to eq(:fallback)
  end
end
