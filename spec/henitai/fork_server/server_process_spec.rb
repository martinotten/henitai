# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::ForkServer::ServerProcess, :aggregate_failures do
  let(:integration) { instance_double(Henitai::Integration::Rspec) }

  it "keeps its connection out of the mutant processes the parent forks later" do
    allow(Process).to receive(:fork).and_return(4242)
    client = nil

    Dir.mktmpdir do |dir|
      client = described_class.start(integration:, mutants: [], test_files: [], log_path: File.join(dir, "s.log"))

      expect(Henitai::InheritedFdRegistry.registered).to include(client.io)
    ensure
      client&.shutdown
    end

    expect(Henitai::InheritedFdRegistry.registered).not_to include(client.io)
  end
end
