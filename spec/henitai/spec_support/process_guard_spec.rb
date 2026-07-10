# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::SpecSupport::ProcessGuard do
  before { described_class.reset! }
  after { described_class.reset! }

  it "reports a process attempt even when the immediate error is rescued" do
    begin
      described_class.block!("Process.fork")
    rescue described_class::ForbiddenProcess
      nil
    end

    expect { described_class.verify! }.to raise_error(
      described_class::ForbiddenProcess,
      "process-free spec attempted: Process.fork"
    )
  end

  it "clears recorded attempts after verification" do
    expect { described_class.verify! }.not_to raise_error
  end
end
