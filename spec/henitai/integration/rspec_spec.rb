# frozen_string_literal: true

require "fileutils"
require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::Integration::Rspec do
  def with_temp_workspace
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) { yield dir }
    end
  end

  def write_file(dir, relative_path, source)
    path = File.join(dir, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, source)
    path
  end

  def sample_source
    <<~RUBY
      class Sample
        def value
        end
      end
    RUBY
  end

  def sample_spec_source
    <<~RUBY
      require_relative "../lib/sample"

      RSpec.describe Sample do
        it "mentions Sample#value" do
        end
      end
    RUBY
  end

  def support_spec_source
    <<~RUBY
      require_relative "support/sample_support"

      RSpec.describe "support loader" do
        it "loads the helper" do
        end
      end
    RUBY
  end

  def require_spec_source
    <<~RUBY
      require "lib/sample"

      RSpec.describe Sample do
        it "loads the helper through require" do
        end
      end
    RUBY
  end

  def cyclic_a_spec_source
    <<~RUBY
      require_relative "cyclic_b_spec"

      RSpec.describe "cycle a" do
        it "loads the other side" do
        end
      end
    RUBY
  end

  def cyclic_b_spec_source
    <<~RUBY
      require_relative "cyclic_a_spec"

      RSpec.describe "cycle b" do
        it "loads the other side" do
        end
      end
    RUBY
  end

  def unrelated_spec_source
    <<~RUBY
      RSpec.describe String do
        it "does not mention the subject" do
        end
      end
    RUBY
  end

  def stub_timeout_child(integration, record, child_pid:, raise_esrch_on_kill: false)
    stub_process_exit(record)
    stub_process_fork(record, child_pid)
    stub_process_wait(record)
    stub_process_clock
    stub_process_kill(record, raise_esrch_on_kill)
    stub_mutant_runtime(integration)
  end

  def stub_process_exit(record)
    allow(Process).to receive(:exit) { |status| record[:child_status] = status }
  end

  def stub_process_fork(record, child_pid)
    allow(Process).to receive(:fork) do |&block|
      record[:forked] = true
      block.call
      child_pid
    end
  end

  def stub_process_wait(record)
    allow(Process).to receive(:wait) do |pid, flags = nil|
      if flags == Process::WNOHANG
        nil
      else
        record[:reaped] = pid
        pid
      end
    end
  end

  def stub_process_clock
    allow(Process).to receive(:clock_gettime).and_return(0.0, 0.2)
  end

  def stub_process_kill(record, raise_esrch_on_kill)
    allow(Process).to receive(:kill) do |signal, pid|
      record[:signals] << [signal, pid]
      raise Errno::ESRCH if raise_esrch_on_kill && signal == :SIGKILL
    end
  end

  def stub_mutant_runtime(integration)
    allow(Henitai::Mutant::Activator).to receive(:activate!).and_return(0)
    allow(integration).to receive_messages(run_tests: 0, pause: nil)
  end

  def stub_ordered_mutant_run(order, integration, child_pid:)
    stub_ordered_exit(order)
    stub_ordered_fork(order, child_pid)
    stub_ordered_activation(order)
    stub_ordered_rspec(order)
    stub_ordered_wait(integration, order)
  end

  def stub_ordered_exit(order)
    allow(Process).to receive(:exit) { |status| order << [:exit, status] }
  end

  def stub_ordered_fork(order, child_pid)
    allow(Process).to receive(:fork) do |&block|
      order << :fork
      block.call
      child_pid
    end
  end

  def stub_ordered_activation(order)
    allow(Henitai::Mutant::Activator).to receive(:activate!) do |_mutant|
      order << :activate
      0
    end
  end

  def stub_ordered_rspec(order)
    allow(RSpec::Core::Runner).to receive(:run) do |test_files|
      order << [:rspec, test_files]
      0
    end
  end

  def stub_ordered_wait(integration, order)
    allow(integration).to receive(:wait_with_timeout) do |pid, timeout|
      order << [:wait, pid, timeout]
      :survived
    end
  end

  it "runs the full suite" do
    integration = described_class.new

    allow(Process).to receive(:exit)
    allow(Process).to receive(:fork) do |&block|
      block.call
      4321
    end
    allow(Process).to receive(:wait).with(4321, Process::WNOHANG).and_return(4321)
    allow(Process).to receive(:last_status).and_return(
      Struct.new(:success?).new(true)
    )
    allow(integration).to receive(:run_tests).and_return(0)

    expect(integration.run_suite(["spec/foo_spec.rb"])).to eq(:survived)
  end

  it "passes the configured timeout through the suite wait path" do
    integration = described_class.new

    allow(Process).to receive(:exit)
    allow(Process).to receive(:fork) do |&block|
      block.call
      4321
    end
    allow(integration).to receive_messages(run_tests: 0, wait_with_timeout: :timeout)

    integration.run_suite(["spec/foo_spec.rb"], timeout: 12.5)

    expect(integration).to have_received(:wait_with_timeout).with(4321, 12.5)
  end

  it "does not activate a mutant when running the full suite" do
    integration = described_class.new

    allow(Process).to receive(:exit)
    allow(Process).to receive(:fork) do |&block|
      block.call
      4321
    end
    allow(Process).to receive(:wait).with(4321, Process::WNOHANG).and_return(4321)
    allow(Process).to receive(:last_status).and_return(
      Struct.new(:success?).new(true)
    )
    allow(integration).to receive(:run_tests).and_return(0)
    allow(Henitai::Mutant::Activator).to receive(:activate!)

    integration.run_suite(["spec/foo_spec.rb"])

    expect(Henitai::Mutant::Activator).not_to have_received(:activate!)
  end

  it "forks a child, sets the mutant id, and waits with timeout" do
    mutant = Struct.new(:id).new("mutant-1")
    integration = described_class.new
    record = {}
    original_env = ENV.fetch("HENITAI_MUTANT_ID", nil)

    begin
      allow(Process).to receive(:exit) { |status| record[:child_status] = status }
      allow(Process).to receive(:fork) do |&block|
        record[:forked] = true
        block.call
        record[:env_id] = ENV.fetch("HENITAI_MUTANT_ID", nil)
        4321
      end
      allow(Henitai::Mutant::Activator).to receive(:activate!).and_return(0)
      allow(integration).to receive(:run_tests).and_return(0)
      allow(Process).to receive(:wait) do |pid, flags|
        record[:wait_args] = [pid, flags]
        4321
      end
      allow(Process).to receive(:last_status).and_return(
        Struct.new(:success?).new(true)
      )

      integration.run_mutant(
        mutant:,
        test_files: ["spec/foo_spec.rb"],
        timeout: 1.5
      )

      expect(record).to include(
        forked: true,
        child_status: 0,
        env_id: "mutant-1",
        wait_args: [4321, Process::WNOHANG]
      )
    ensure
      ENV["HENITAI_MUTANT_ID"] = original_env
    end
  end

  it "activates the mutant before running child tests" do
    mutant = Struct.new(:id).new("mutant-2")
    integration = described_class.new
    order = []
    original_env = ENV.fetch("HENITAI_MUTANT_ID", nil)

    begin
      stub_ordered_mutant_run(order, integration, child_pid: 9876)

      integration.run_mutant(
        mutant:,
        test_files: ["spec/bar_spec.rb"],
        timeout: 2.0
      )

      expect(order).to eq(
        [
          :fork,
          :activate,
          [
            :rspec,
            ["spec/bar_spec.rb", "--require", "henitai/coverage_formatter"]
          ],
          [:exit, 0],
          [:wait, 9876, 2.0]
        ]
      )
    ensure
      ENV["HENITAI_MUTANT_ID"] = original_env
    end
  end

  it "converts a true rspec result to a survived mutant" do
    mutant = Struct.new(:id).new("mutant-true")
    integration = described_class.new
    record = {}
    original_env = ENV.fetch("HENITAI_MUTANT_ID", nil)

    begin
      allow(Process).to receive(:exit) { |status| record[:child_status] = status }
      allow(Process).to receive(:fork) do |&block|
        block.call
        24_601
      end
      allow(Henitai::Mutant::Activator).to receive(:activate!).and_return(0)
      allow(RSpec::Core::Runner).to receive(:run).and_return(true)
      allow(integration).to receive(:pause).and_return(nil)
      allow(Process).to receive(:wait).and_return(24_601)
      allow(Process).to receive_messages(
        last_status: Struct.new(:success?).new(true)
      )

      record[:result] = integration.run_mutant(
        mutant:,
        test_files: ["spec/passing_spec.rb"],
        timeout: 0.1
      )

      expect(record[:result]).to eq(:survived)
    ensure
      ENV["HENITAI_MUTANT_ID"] = original_env
    end
  end

  it "converts a false rspec result to a killed mutant" do
    mutant = Struct.new(:id).new("mutant-false")
    integration = described_class.new
    record = {}
    original_env = ENV.fetch("HENITAI_MUTANT_ID", nil)

    begin
      allow(Process).to receive(:exit) { |status| record[:child_status] = status }
      allow(Process).to receive(:fork) do |&block|
        block.call
        24_602
      end
      allow(Henitai::Mutant::Activator).to receive(:activate!).and_return(0)
      allow(RSpec::Core::Runner).to receive(:run).and_return(false)
      allow(integration).to receive(:pause).and_return(nil)
      allow(Process).to receive(:wait).and_return(24_602)
      allow(Process).to receive_messages(
        last_status: Struct.new(:success?).new(false)
      )

      record[:result] = integration.run_mutant(
        mutant:,
        test_files: ["spec/failing_spec.rb"],
        timeout: 0.1
      )

      expect(record[:result]).to eq(:killed)
    ensure
      ENV["HENITAI_MUTANT_ID"] = original_env
    end
  end

  it "requires the coverage formatter in rspec options" do
    mutant = Struct.new(:id).new("mutant-coverage")
    integration = described_class.new
    record = {}
    original_env = ENV.fetch("HENITAI_MUTANT_ID", nil)

    begin
      allow(Process).to receive(:exit)
      allow(Process).to receive(:fork) do |&block|
        block.call
        24_604
      end
      allow(Henitai::Mutant::Activator).to receive(:activate!).and_return(0)
      allow(RSpec::Core::Runner).to receive(:run) do |args|
        record[:args] = args
        0
      end
      allow(integration).to receive(:wait_with_timeout).and_return(:survived)

      integration.run_mutant(
        mutant:,
        test_files: ["spec/coverage_spec.rb"],
        timeout: 0.1
      )

      expect(record[:args]).to include("--require", "henitai/coverage_formatter")
    ensure
      ENV["HENITAI_MUTANT_ID"] = original_env
    end
  end

  it "keeps waiting when the child has not exited yet" do
    mutant = Struct.new(:id).new("mutant-loop")
    integration = described_class.new
    record = { pauses: [] }
    original_env = ENV.fetch("HENITAI_MUTANT_ID", nil)

    begin
      allow(Process).to receive(:exit) { |status| record[:child_status] = status }
      allow(Process).to receive(:fork) do |&block|
        block.call
        24_603
      end
      allow(Henitai::Mutant::Activator).to receive(:activate!).and_return(0)
      allow(RSpec::Core::Runner).to receive(:run).and_return(true)
      allow(integration).to receive(:pause) do |seconds|
        record[:pauses] << seconds
      end
      allow(Process).to receive(:wait).and_return(nil, 24_603)
      allow(Process).to receive(:clock_gettime).and_return(0.0, 0.05, 0.05)
      allow(Process).to receive_messages(
        last_status: Struct.new(:success?).new(true)
      )

      integration.run_mutant(
        mutant:,
        test_files: ["spec/pending_spec.rb"],
        timeout: 0.1
      )

      expect(record).to include(
        pauses: [0.01],
        child_status: 0
      )
    ensure
      ENV["HENITAI_MUTANT_ID"] = original_env
    end
  end

  it "escalates a stuck child from SIGTERM to SIGKILL" do
    mutant = Struct.new(:id).new("mutant-3")
    integration = described_class.new
    record = { pauses: [], signals: [] }
    original_env = ENV.fetch("HENITAI_MUTANT_ID", nil)

    begin
      stub_timeout_child(integration, record, child_pid: 2468)
      allow(integration).to receive(:pause) do |seconds|
        record[:pauses] << seconds
      end

      integration.run_mutant(
        mutant:,
        test_files: ["spec/baz_spec.rb"],
        timeout: 0.1
      )

      expect(record).to include(
        signals: [[:SIGTERM, 2468], [:SIGKILL, 2468]],
        forked: true,
        child_status: 0
      )
    ensure
      ENV["HENITAI_MUTANT_ID"] = original_env
    end
  end

  it "reaps a timed-out child even if it exits after SIGTERM" do
    mutant = Struct.new(:id).new("mutant-3b")
    integration = described_class.new
    record = { signals: [] }
    original_env = ENV.fetch("HENITAI_MUTANT_ID", nil)

    begin
      stub_timeout_child(
        integration,
        record,
        child_pid: 2469,
        raise_esrch_on_kill: true
      )

      integration.run_mutant(
        mutant:,
        test_files: ["spec/baz_spec.rb"],
        timeout: 0.1
      )

      expect(record).to include(
        signals: [[:SIGTERM, 2469], [:SIGKILL, 2469]],
        reaped: 2469,
        forked: true,
        child_status: 0
      )
    ensure
      ENV["HENITAI_MUTANT_ID"] = original_env
    end
  end

  it "exits the child with status 1 when RSpec reports a failure" do
    mutant = Struct.new(:id).new("mutant-4")
    integration = described_class.new
    record = {}
    original_env = ENV.fetch("HENITAI_MUTANT_ID", nil)

    begin
      allow(Process).to receive(:exit) { |status| record[:child_status] = status }
      allow(Process).to receive(:fork) do |&block|
        block.call
        1357
      end
      allow(Process).to receive_messages(
        wait: 1357,
        last_status: Struct.new(:success?).new(false)
      )
      allow(Henitai::Mutant::Activator).to receive(:activate!).and_return(0)
      allow(integration).to receive(:pause).and_return(nil)
      allow(RSpec::Core::Runner).to receive(:run) do |test_files|
        record[:rspec_files] = test_files
        1
      end

      integration.run_mutant(
        mutant:,
        test_files: ["spec/failing_spec.rb"],
        timeout: 0.1
      )

      expect(record).to include(
        rspec_files: [
          "spec/failing_spec.rb",
          "--require",
          "henitai/coverage_formatter"
        ],
        child_status: 1
      )
    ensure
      ENV["HENITAI_MUTANT_ID"] = original_env
    end
  end

  it "marks unsupported activations as compile errors" do
    mutant = Struct.new(:id).new("mutant-compile-error")
    integration = described_class.new
    record = {}
    original_env = ENV.fetch("HENITAI_MUTANT_ID", nil)

    begin
      allow(Process).to receive(:exit) { |status| record[:child_status] = status }
      allow(Process).to receive(:fork) do |&block|
        block.call
        24_605
      end
      allow(Henitai::Mutant::Activator).to receive(:activate!).and_return(:compile_error)
      allow(integration).to receive(:pause).and_return(nil)
      allow(Process).to receive(:wait).and_return(24_605)
      allow(Process).to receive_messages(
        last_status: Struct.new(:success?, :exitstatus).new(false, 2)
      )

      result = integration.run_mutant(
        mutant:,
        test_files: ["spec/compile_error_spec.rb"],
        timeout: 0.1
      )

      expect(record[:child_status]).to eq(2)
      expect(result.status).to eq(:compile_error)
    ensure
      ENV["HENITAI_MUTANT_ID"] = original_env
    end
  end

  it "selects matching spec files by subject expression" do
    with_temp_workspace do |dir|
      source_path = write_file(dir, "lib/sample.rb", sample_source)

      write_file(dir, "spec/sample_spec.rb", sample_spec_source)

      write_file(dir, "spec/unrelated_spec.rb", unrelated_spec_source)

      subject = Henitai::Subject.new(
        namespace: "Sample",
        method_name: "value",
        source_location: {
          file: source_path,
          range: 1..4
        }
      )

      expect(described_class.new.select_tests(subject)).to eq(["spec/sample_spec.rb"])
    end
  end

  it "falls back to source-file based selection when no direct match exists" do
    with_temp_workspace do |dir|
      source_path = write_file(dir, "lib/sample.rb", sample_source)

      write_file(
        dir,
        "spec/other_spec.rb",
        <<~RUBY
          RSpec.describe String do
            it "does not mention the subject" do
            end
          end
        RUBY
      )

      subject = Henitai::Subject.new(
        namespace: "Example",
        method_name: "value",
        source_location: {
          file: source_path,
          range: 1..4
        }
      )

      expect(described_class.new.select_tests(subject)).to contain_exactly(
        "spec/other_spec.rb"
      )
    end
  end

  it "falls back through transitive requires when no direct match exists" do
    with_temp_workspace do |dir|
      source_path = write_file(dir, "lib/sample.rb", sample_source)

      write_file(
        dir,
        "spec/support/sample_support.rb",
        <<~RUBY
          require_relative "../../lib/sample"
        RUBY
      )

      write_file(dir, "spec/sample_spec.rb", support_spec_source)

      subject = Henitai::Subject.new(
        namespace: "Sample",
        method_name: "value",
        source_location: {
          file: source_path,
          range: 1..4
        }
      )

      expect(described_class.new.select_tests(subject)).to eq(["spec/sample_spec.rb"])
    end
  end

  it "follows plain requires when selecting fallback spec files" do
    with_temp_workspace do |dir|
      source_path = write_file(dir, "lib/sample.rb", sample_source)

      write_file(dir, "spec/require_spec.rb", require_spec_source)

      subject = Henitai::Subject.new(
        namespace: "Example",
        method_name: "value",
        source_location: {
          file: source_path,
          range: 1..4
        }
      )

      expect(described_class.new.select_tests(subject)).to eq(["spec/require_spec.rb"])
    end
  end

  it "avoids infinite loops when requires cycle" do
    with_temp_workspace do |dir|
      source_path = write_file(dir, "lib/sample.rb", sample_source)

      write_file(dir, "spec/cyclic_a_spec.rb", cyclic_a_spec_source)
      write_file(dir, "spec/cyclic_b_spec.rb", cyclic_b_spec_source)

      subject = Henitai::Subject.new(
        namespace: "Example",
        method_name: "value",
        source_location: {
          file: source_path,
          range: 1..4
        }
      )

      expect(described_class.new.select_tests(subject)).to contain_exactly(
        "spec/cyclic_a_spec.rb",
        "spec/cyclic_b_spec.rb"
      )
    end
  end

  it "returns no tests when the subject has no source file and no direct match" do
    with_temp_workspace do
      write_file(Dir.pwd, "spec/other_spec.rb", unrelated_spec_source)

      subject = Henitai::Subject.new(namespace: "Sample", method_name: "value")

      expect(described_class.new.select_tests(subject)).to eq([])
    end
  end

  it "writes child stdout and stderr into the combined scenario log" do
    with_temp_workspace do |dir|
      test_file = write_file(dir, "spec/sample_spec.rb", sample_spec_source)
      stdout_source = write_file(dir, "captured_stdout.txt", "captured stdout\n")
      mutant = Struct.new(:id).new("mutant-1")
      integration = described_class.new
      original_env = ENV.fetch("HENITAI_MUTANT_ID", nil)

      begin
        allow(Process).to receive(:exit)
        allow(Process).to receive(:fork) do |_args, &block|
          block.call
          4321
        end
        allow(Process).to receive(:wait).with(4321, Process::WNOHANG).and_return(4321)
        allow(Process).to receive(:last_status).and_return(
          Struct.new(:success?, :exitstatus).new(true, 0)
        )
        allow(Henitai::Mutant::Activator).to receive(:activate!).and_return(0)
        allow(integration).to receive(:run_tests) do |_test_files|
          File.open(stdout_source, "rb") do |file|
            IO.copy_stream(file, $stdout)
          end
          warn "captured stderr"
          0
        end

        result = integration.run_mutant(
          mutant:,
          test_files: [test_file],
          timeout: 1.0
        )

        expect(File.read(result.log_path)).to eq(result.combined_output)
      ensure
        ENV["HENITAI_MUTANT_ID"] = original_env
      end
    end
  end
end
