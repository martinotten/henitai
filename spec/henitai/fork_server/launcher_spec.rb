# frozen_string_literal: true

require "spec_helper"
require "stringio"

# Process-free: `Process.fork` is stubbed, so this file runs inside a mutant
# child and through bin/verify-process-free-specs. The real fork is covered by
# launcher_process_spec.rb.
# rubocop:disable RSpec/MultipleMemoizedHelpers
RSpec.describe Henitai::ForkServer::Launcher, :aggregate_failures do
  let(:mutant) { instance_double(Henitai::Mutant, id: "m1") }
  let(:mutants) { { "m1" => mutant } }
  let(:integration) { instance_double(Henitai::Integration::Rspec) }
  let(:socket) { StringIO.new }
  let(:server_pid) { 4_242 }
  let(:launcher) { described_class.new(integration:, mutants:, socket:, server_pid:) }
  let(:pid) { 9_001 }
  let(:request) do
    {
      "mutant_id" => "m1",
      "test_files" => ["a_spec.rb"],
      "log_paths" => { "report_path" => "reports/m1.json" },
      "env" => { "HENITAI_SPEC_PROBE" => "from-request" }
    }
  end

  before { allow(Process).to receive(:fork).and_return(pid) }

  it "hands the scheduler the pid of the process it forked" do
    expect(launcher.call(request)).to eq(pid)
    expect(Process).to have_received(:fork).once
  end

  it "refuses a request for a mutant this run does not have" do
    expect { launcher.call(request.merge("mutant_id" => "ghost")) }
      .to raise_error(KeyError, "unknown mutant ghost")
  end

  it "requires the request to carry the mutant's log paths" do
    expect { launcher.call(request.except("log_paths")) }.to raise_error(KeyError, /log_paths/)
  end

  describe "the work it does in the forked process" do
    before do
      allow(Henitai::Integration::ChildBootstrap).to receive(:after_fork!)
      allow(integration).to receive(:run_in_child).and_return(0)
      allow(Process).to receive(:exit)
    end

    # The child's environment is this process's environment once the fork block
    # is lifted, so every example restores the keys it touches.
    around do |example|
      saved = ENV.to_h.slice("HENITAI_MUTANT_ID", "HENITAI_SPEC_PROBE")
      example.run
    ensure
      %w[HENITAI_MUTANT_ID HENITAI_SPEC_PROBE].each do |key|
        saved.key?(key) ? ENV[key] = saved[key] : ENV.delete(key)
      end
    end

    # Lifts the block Process.fork would run and calls it here, so the child
    # sequence is asserted without forking.
    def run_child_work(target = launcher, payload = request)
      forked = nil
      allow(Process).to receive(:fork) do |&work|
        forked = work
        9_001
      end
      target.call(payload)
      forked.call
    end

    it "closes the server connection, so the server notices the fork" do
      run_child_work

      expect(socket).to be_closed
    end

    it "boots the child against the server it was forked from" do
      run_child_work

      expect(Henitai::Integration::ChildBootstrap).to have_received(:after_fork!).with(parent_pid: server_pid)
    end

    it "defaults the parent pid to the process doing the forking" do
      run_child_work(described_class.new(integration:, mutants:, socket:))

      expect(Henitai::Integration::ChildBootstrap).to have_received(:after_fork!).with(parent_pid: Process.pid)
    end

    it "runs the tests with the mutant's files and symbol log paths" do
      run_child_work

      expect(integration).to have_received(:run_in_child).with(
        mutant:, test_files: ["a_spec.rb"], log_paths: { report_path: "reports/m1.json" }
      )
    end

    it "runs no test files when the request names none" do
      run_child_work(launcher, request.except("test_files"))

      expect(integration).to have_received(:run_in_child).with(hash_including(test_files: []))
    end

    it "exports the request's environment and the mutant id to the child" do
      run_child_work

      expect([ENV.fetch("HENITAI_SPEC_PROBE"), ENV.fetch("HENITAI_MUTANT_ID")])
        .to eq(%w[from-request m1])
    end

    it "keeps the run's mutant id when the request env would overwrite it" do
      run_child_work(launcher, request.merge("env" => { "HENITAI_MUTANT_ID" => "from-request" }))

      expect(ENV.fetch("HENITAI_MUTANT_ID")).to eq("m1")
    end

    it "leaves the inherited environment alone when the request carries none" do
      ENV["HENITAI_SPEC_PROBE"] = "inherited"

      run_child_work(launcher, request.except("env"))

      expect([ENV.fetch("HENITAI_SPEC_PROBE"), ENV.fetch("HENITAI_MUTANT_ID")])
        .to eq(%w[inherited m1])
    end

    it "exits with the status the tests ended in" do
      allow(integration).to receive(:run_in_child).and_return(3)

      run_child_work

      expect(Process).to have_received(:exit).with(3)
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
