# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Integration::RspecProcessRunner do
  def mutant_input
    Struct.new(:id).new("abc")
  end

  it "exports the mutant id to a spawned child" do
    reader, writer = IO.pipe
    integration = instance_double(Henitai::Integration::Rspec)
    allow(integration).to receive(:run_in_child) do |**|
      writer.write(ENV.fetch("HENITAI_MUTANT_ID"))
      writer.close
      0
    end

    handle = described_class.new.spawn_mutant(
      integration,
      mutant: mutant_input,
      test_files: [],
      log_paths: {}
    )
    Process.wait(handle.pid)
    writer.close unless writer.closed?

    expect(reader.read).to eq("abc")
  ensure
    reader&.close unless reader&.closed?
    writer&.close unless writer&.closed?
  end
end
