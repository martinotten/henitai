# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Integration::ChildBootstrap do
  # Pure ordering/dispatch checks with doubles; no forking here. The real
  # post-fork path is covered by orphan_watchdog_process_spec.rb and
  # rspec_process_runner_process_spec.rb.
  let(:calls) { [] }

  before do
    allow(Henitai::InheritedFdRegistry).to receive(:close_all!) { calls << :close_fds }
    allow(Process).to receive(:setpgid) { calls << :setpgid }
    allow(Henitai::OrphanWatchdog).to receive(:start) { calls << :watchdog }
    allow(Signal).to receive(:trap) { |signal, _handler| calls << [:trap, signal] }
  end

  it "closes inherited handles before anything else can fail" do
    described_class.after_fork!(parent_pid: 4_242)

    expect(calls.first).to eq(:close_fds)
  end

  it "runs the full bootstrap sequence in order" do
    described_class.after_fork!(parent_pid: 4_242)

    expect(calls).to eq([:close_fds, [:trap, "INT"], [:trap, "TERM"], [:trap, "HUP"], [:trap, "CHLD"],
                         :setpgid, :watchdog])
  end

  it "restores default handling of the signals the parent traps" do
    described_class.after_fork!(parent_pid: 4_242)

    %w[INT TERM HUP CHLD].each do |signal|
      expect(Signal).to have_received(:trap).with(signal, "DEFAULT")
    end
  end

  it "puts the child in its own process group" do
    described_class.after_fork!(parent_pid: 4_242)

    expect(Process).to have_received(:setpgid).with(0, 0)
  end

  it "hands the watchdog the parent pid captured before the fork" do
    described_class.after_fork!(parent_pid: 4_242)

    expect(Henitai::OrphanWatchdog).to have_received(:start).with(parent_pid: 4_242)
  end

  it "still closes handles and sets the process group when the watchdog is disabled" do
    allow(Henitai::OrphanWatchdog).to receive(:start).and_return(nil)

    described_class.after_fork!(parent_pid: 4_242)

    expect(calls.grep_v(Array)).to eq(%i[close_fds setpgid])
  end
end
