# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpec/MultipleMemoizedHelpers
RSpec.describe Henitai::ExecutionEngine::ForkServerScope, :aggregate_failures do
  let(:host_class) do
    Class.new do
      include Henitai::ExecutionEngine::ForkServerScope

      attr_reader :warnings, :inside, :options

      def initialize
        @warnings = []
      end

      def run(mutants, integration, config)
        with_fork_server(mutants, integration, config) do
          @inside = @fork_server_runner
          @options = parallel_runtime_options
        end
      end

      def includes_boot?
        calibration_includes_boot?
      end

      def warn(message)
        @warnings << message
      end

      def prioritized_tests_for(_mutant, _integration, _config)
        ["a_spec.rb"]
      end

      def resolved_timeout(test_files, _config, include_boot: calibration_includes_boot?)
        [test_files, include_boot]
      end
    end
  end
  let(:host) { host_class.new }
  let(:config) { instance_double(Henitai::Configuration, fork_server: true, reports_dir: "reports") }
  let(:integration) { instance_double(Henitai::Integration::Rspec, fork_server_supported?: true) }
  let(:runner) { instance_double(Henitai::ForkServer::MutantRunner, stop: nil, active?: true, runtime: nil) }
  let(:mutants) { [instance_double(Henitai::Mutant)] }

  before { allow(Henitai::ForkServer).to receive(:start).and_return(runner) }

  it "runs the block with the server's runner and stops it afterwards" do
    host.run(mutants, integration, config)

    expect(host.inside).to eq(runner)
    expect(runner).to have_received(:stop)
    expect(Henitai::ForkServer).to have_received(:start)
      .with(hash_including(integration:, mutants:, test_files: ["a_spec.rb"],
                           log_path: "reports/mutation-logs/fork-server.log"))
  end

  it "hands the server a timeout for fallback runs that includes booting the suite" do
    host.run(mutants, integration, config)

    expect(Henitai::ForkServer).to have_received(:start) do |fallback_timeout:, **|
      expect(fallback_timeout.call(["a_spec.rb"])).to eq([["a_spec.rb"], true])
    end
  end

  it "does not start a server when the flag is off" do
    allow(config).to receive(:fork_server).and_return(false)

    host.run(mutants, integration, config)

    expect(Henitai::ForkServer).not_to have_received(:start)
  end

  it "warns and uses per-mutant boot for an unsupported integration" do
    allow(integration).to receive(:fork_server_supported?).and_return(false)

    host.run(mutants, integration, config)

    expect(host.inside).to be_nil
    expect(host.warnings.first).to include("not supported for this integration")
  end

  it "uses per-mutant boot when the server failed to boot" do
    allow(Henitai::ForkServer).to receive(:start).and_return(nil)

    host.run(mutants, integration, config)

    expect(host.inside).to be_nil
  end

  it "excludes boot from the timeout calibration only while the server is active" do
    host.run(mutants, integration, config)

    expect(host.includes_boot?).to be(true)
  end

  it "hands the scheduler the server's runtime while the server is active" do
    allow(runner).to receive(:runtime).and_return(:server_runtime)
    host.run(mutants, integration, config)

    expect(host.options).to eq(runtime: :server_runtime)
  end

  it "leaves the scheduler's runtime alone without an active server" do
    allow(config).to receive(:fork_server).and_return(false)
    host.run(mutants, integration, config)

    expect(host.options).to eq({})
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
