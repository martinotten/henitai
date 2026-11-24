# frozen_string_literal: true

# rubocop:disable RSpec/SpecFilePathFormat

require "spec_helper"

RSpec.describe Henitai::SpecSupport::ProcessGuard::KillGuard do
  let(:forbidden) { Henitai::SpecSupport::ProcessGuard::ForbiddenProcess }
  let(:forwarding_class) do
    klass = Class.new { def self.kill(*args) = [:real_kill, *args] }
    klass.singleton_class.prepend(described_class)
    klass
  end

  after { Henitai::SpecSupport::ProcessGuard.reset! }

  it "blocks a signal sent to a foreign pid" do
    expect { forwarding_class.kill(:SIGTERM, 1000) }
      .to raise_error(forbidden, /Process\.kill/)
  end

  it "allows an integer signal-0 liveness probe to any pid" do
    expect(forwarding_class.kill(0, -1000)).to eq([:real_kill, 0, -1000])
  end

  it "allows a string signal-0 liveness probe" do
    expect(forwarding_class.kill("0", 1000)).to eq([:real_kill, "0", 1000])
  end

  it "allows a symbol signal-0 liveness probe" do
    expect(forwarding_class.kill(:"0", 1000)).to eq([:real_kill, :"0", 1000])
  end

  it "allows a real signal sent to the current process" do
    expect(forwarding_class.kill(:SIGTERM, Process.pid)).to eq([:real_kill, :SIGTERM, Process.pid])
  end
end

# rubocop:enable RSpec/SpecFilePathFormat
