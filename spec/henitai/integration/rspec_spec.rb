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
    stub_child_logging(integration)
    stub_process_exit(record)
    stub_process_fork(record, child_pid)
    stub_process_wait(record)
    stub_process_clock
    stub_process_kill(record, raise_esrch_on_kill)
    stub_mutant_runtime(integration)
  end

  def stub_child_logging(integration)
    log_support = instance_double(Henitai::Integration::ScenarioLogSupport)

    allow(integration).to receive(:scenario_log_support).and_return(log_support)
    allow(log_support).to receive(:with_coverage_dir).and_yield
    allow(log_support).to receive(:capture_child_output).and_yield
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
    stub_child_logging(integration)
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

  def stub_timeout_boundary_run(integration, record)
    stub_child_logging(integration)
    stub_timeout_boundary_exit(record)
    stub_timeout_boundary_fork(record)
    stub_timeout_boundary_activation
    stub_timeout_boundary_rspec
    stub_timeout_boundary_pause(integration, record)
    stub_timeout_boundary_wait(record)
    stub_timeout_boundary_clock
    stub_timeout_boundary_status
  end

  def stub_timeout_boundary_exit(record)
    allow(Process).to receive(:exit) { |status| record[:child_status] = status }
  end

  def stub_timeout_boundary_fork(record)
    allow(Process).to receive(:fork) do |&block|
      record[:forked] = true
      block.call
      24_610
    end
  end

  def stub_timeout_boundary_activation
    allow(Henitai::Mutant::Activator).to receive(:activate!).and_return(0)
  end

  def stub_timeout_boundary_rspec
    allow(RSpec::Core::Runner).to receive(:run).and_return(true)
  end

  def stub_timeout_boundary_pause(integration, record)
    allow(integration).to receive(:pause) { |seconds| record[:pauses] << seconds }
  end

  def stub_timeout_boundary_wait(record)
    allow(Process).to receive(:wait) do |pid, _flags|
      record[:waits] += 1
      record[:waits] == 3 ? pid : nil
    end
  end

  def stub_timeout_boundary_clock
    allow(Process).to receive(:clock_gettime).and_return(0.0, 0.05, 0.1)
  end

  def stub_timeout_boundary_status
    allow(Process).to receive_messages(last_status: Struct.new(:success?).new(true))
  end

  it "runs the full suite" do
    integration = described_class.new

    with_temp_workspace do
      allow(Process).to receive(:spawn).and_return(4321)
      allow(integration).to receive(:wait_with_timeout).and_return(
        Struct.new(:success?, :exitstatus).new(true, 0)
      )

      expect(integration.run_suite(["spec/foo_spec.rb"])).to eq(:survived)
    end
  end

  it "uses the baseline log paths when running the full suite" do
    integration = described_class.new

    with_temp_workspace do |dir|
      log_paths = {
        stdout_path: File.join(dir, "reports", "mutation-logs", "baseline.stdout.log"),
        stderr_path: File.join(dir, "reports", "mutation-logs", "baseline.stderr.log"),
        log_path: File.join(dir, "reports", "mutation-logs", "baseline.log")
      }

      allow(integration).to receive(:scenario_log_paths).with("baseline").and_return(
        log_paths
      )
      allow(Process).to receive(:spawn).and_return(4321)
      allow(integration).to receive(:wait_with_timeout).and_return(
        Struct.new(:success?, :exitstatus).new(true, 0)
      )

      integration.run_suite(["spec/foo_spec.rb"])

      expect(integration).to have_received(:scenario_log_paths).with("baseline")
    end
  end

  it "resolves the rspec and minitest integrations" do
    expect(
      [
        Henitai::Integration.for("rspec"),
        Henitai::Integration.for("minitest")
      ]
    ).to eq(
      [
        described_class,
        Henitai::Integration::Minitest
      ]
    )
  end

  it "raises a helpful error for an unknown integration" do
    expect { Henitai::Integration.for("unknown") }
      .to raise_error(
        ArgumentError,
        "Unknown integration: unknown. Available: minitest, rspec"
      )
  end

  it "keeps the base integration abstract" do
    integration = Henitai::Integration::Base.new

    expect { integration.select_tests(nil) }.to raise_error(NotImplementedError)
  end

  it "keeps the base integration test files abstract" do
    integration = Henitai::Integration::Base.new

    expect { integration.test_files }.to raise_error(NotImplementedError)
  end

  it "keeps the base integration mutant runner abstract" do
    integration = Henitai::Integration::Base.new

    expect do
      integration.run_mutant(mutant: nil, test_files: [], timeout: 1.0)
    end.to raise_error(NotImplementedError)
  end

  it "passes the configured timeout through the suite wait path" do
    integration = described_class.new

    with_temp_workspace do
      allow(Process).to receive(:spawn).and_return(4321)
      allow(integration).to receive(:wait_with_timeout).and_return(:timeout)

      integration.run_suite(["spec/foo_spec.rb"], timeout: 12.5)

      expect(integration).to have_received(:wait_with_timeout).with(4321, 12.5)
    end
  end

  it "does not activate a mutant when running the full suite" do
    integration = described_class.new

    with_temp_workspace do
      allow(Process).to receive(:spawn).and_return(4321)
      allow(integration).to receive(:wait_with_timeout).and_return(
        Struct.new(:success?, :exitstatus).new(true, 0)
      )
      allow(Henitai::Mutant::Activator).to receive(:activate!)

      integration.run_suite(["spec/foo_spec.rb"])

      expect(Henitai::Mutant::Activator).not_to have_received(:activate!)
    end
  end

  it "uses bundle exec rspec for the baseline suite command" do
    integration = described_class.new

    expect(integration.send(:suite_command, ["spec/foo_spec.rb"])).to eq(
      ["bundle", "exec", "rspec", "spec/foo_spec.rb"]
    )
  end

  it "requires the rspec-specific coverage formatter adapter" do
    integration = described_class.new

    expect(integration.send(:rspec_options)).to eq(
      ["--require", "henitai/rspec_coverage_formatter"]
    )
  end

  it "returns the discovered spec files as test files" do
    integration = described_class.new

    allow(integration).to receive(:spec_files).and_return(["spec/a_spec.rb"])

    expect(integration.test_files).to eq(["spec/a_spec.rb"])
  end

  it "forks a child, sets the mutant id, and waits with timeout" do
    mutant = Struct.new(:id).new("mutant-1")
    integration = described_class.new
    record = {}
    original_env = ENV.fetch("HENITAI_MUTANT_ID", nil)

    begin
      stub_child_logging(integration)
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
            ["spec/bar_spec.rb", "--require", "henitai/rspec_coverage_formatter"]
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
      stub_child_logging(integration)
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
      stub_child_logging(integration)
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
      stub_child_logging(integration)
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

      expect(record[:args]).to include("--require", "henitai/rspec_coverage_formatter")
    ensure
      ENV["HENITAI_MUTANT_ID"] = original_env
    end
  end

  it "assigns a unique coverage dir to each mutant child" do
    mutant = Struct.new(:id).new("mutant-coverage-dir")
    integration = described_class.new
    record = {}
    original_env = ENV.fetch("HENITAI_COVERAGE_DIR", nil)

    begin
      log_support = Henitai::Integration::ScenarioLogSupport.new
      allow(log_support).to receive(:capture_child_output).and_yield
      allow(integration).to receive_messages(
        scenario_log_support: log_support,
        wait_with_timeout: :survived
      )
      allow(Process).to receive(:exit)
      allow(Process).to receive(:fork) do |&block|
        block.call
        24_606
      end
      allow(Henitai::Mutant::Activator).to receive(:activate!).and_return(0)
      allow(RSpec::Core::Runner).to receive(:run) do |_args|
        record[:coverage_dir] = ENV.fetch("HENITAI_COVERAGE_DIR", nil)
        0
      end

      integration.run_mutant(
        mutant:,
        test_files: ["spec/coverage_spec.rb"],
        timeout: 0.1
      )

      expect(record[:coverage_dir]).to eq(
        File.join("reports", "mutation-coverage", mutant.id)
      )
    ensure
      ENV["HENITAI_COVERAGE_DIR"] = original_env
    end
  end

  it "keeps waiting when the child has not exited yet" do
    mutant = Struct.new(:id).new("mutant-loop")
    integration = described_class.new
    record = { pauses: [] }
    original_env = ENV.fetch("HENITAI_MUTANT_ID", nil)

    begin
      stub_child_logging(integration)
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

  it "returns the child status when the child exits at the timeout boundary" do
    mutant = Struct.new(:id).new("mutant-3c")
    integration = described_class.new
    record = { waits: 0, pauses: [] }
    original_env = ENV.fetch("HENITAI_MUTANT_ID", nil)

    begin
      stub_timeout_boundary_run(integration, record)

      result = integration.run_mutant(
        mutant:,
        test_files: ["spec/pending_spec.rb"],
        timeout: 0.1
      )

      expect([result, record]).to eq(
        [
          :survived,
          {
            waits: 3,
            pauses: [0.01],
            child_status: 0
          }
        ]
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
      stub_child_logging(integration)
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
          "henitai/rspec_coverage_formatter"
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
      stub_child_logging(integration)
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

      expect(
        {
          child_status: record[:child_status],
          result_status: result.status
        }
      ).to eq(
        child_status: 2,
        result_status: :compile_error
      )
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

  it "falls back when reading a spec file raises during direct matching" do
    integration = described_class.new
    subject = instance_double(
      Henitai::Subject,
      expression: "Sample#value",
      namespace: "Sample"
    )

    allow(integration).to receive(:spec_files).and_return(
      ["spec/broken_spec.rb", "spec/other_spec.rb"]
    )
    allow(File).to receive(:read).with("spec/broken_spec.rb").and_raise(Errno::EACCES)
    allow(File).to receive(:read).with("spec/other_spec.rb").and_return("RSpec.describe String do end")
    allow(integration).to receive(:fallback_spec_files).with(subject).and_return(["spec/fallback_spec.rb"])

    expect(integration.select_tests(subject)).to eq(["spec/fallback_spec.rb"])
  end

  it "skips broken fallback candidates and keeps matching ones" do
    integration = described_class.new
    subject = instance_double(Henitai::Subject, source_file: "lib/sample.rb")

    allow(integration).to receive(:spec_files).and_return(
      ["spec/broken_spec.rb", "spec/matching_spec.rb"]
    )
    allow(integration).to receive(:requires_source_file_transitively?) do |spec_file, _source_file, _visited = []|
      raise Errno::EACCES if spec_file == "spec/broken_spec.rb"

      true
    end

    expect(integration.send(:fallback_spec_files, subject)).to eq(["spec/matching_spec.rb"])
  end

  it "orders selection patterns by longest first and removes duplicates" do
    integration = described_class.new
    subject = instance_double(
      Henitai::Subject,
      expression: "Sample::Thing#value",
      namespace: "Sample::Thing"
    )

    expect(integration.send(:selection_patterns, subject)).to eq(
      ["Sample::Thing#value", "Sample::Thing"]
    )
  end

  it "matches a source file when a spec only mentions the basename" do
    integration = described_class.new
    source_file = "/tmp/project/lib/sample.rb"

    allow(File).to receive(:read).with("spec/sample_spec.rb").and_return(
      'require_relative "../lib/sample"'
    )

    expect(
      integration.send(:requires_source_file?, "spec/sample_spec.rb", source_file)
    ).to be(true)
  end

  it "matches a source file when a spec mentions the full source path" do
    integration = described_class.new
    source_file = "/tmp/project/lib/sample.rb"

    allow(File).to receive(:read).with("spec/sample_spec.rb").and_return(source_file)
    allow(File).to receive(:basename).with(source_file, ".rb").and_return("other_name")

    expect(
      integration.send(:requires_source_file?, "spec/sample_spec.rb", source_file)
    ).to be(true)
  end

  it "stops transitive traversal when the spec file was already visited" do
    integration = described_class.new
    spec_file = File.expand_path("spec/sample_spec.rb")

    expect(
      integration.send(
        :requires_source_file_transitively?,
        spec_file,
        "lib/sample.rb",
        [spec_file]
      )
    ).to be(false)
  end

  it "records the visited spec before traversing its requires" do
    integration = described_class.new
    visited = []

    allow(integration).to receive_messages(
      requires_source_file?: false,
      required_files: []
    )

    integration.send(
      :requires_source_file_transitively?,
      "spec/sample_spec.rb",
      "lib/sample.rb",
      visited
    )

    expect(visited).to include(File.expand_path("spec/sample_spec.rb"))
  end

  it "uses relative candidates when resolving require_relative directives" do
    integration = described_class.new

    allow(integration).to receive(:relative_candidates)
      .with("spec/sample_spec.rb", "../sample")
      .and_return(["relative.rb"])
    allow(integration).to receive(:require_candidates)
    allow(File).to receive(:file?).with("relative.rb").and_return(true)

    expect(
      integration.send(
        :resolve_required_file,
        "spec/sample_spec.rb",
        "require_relative",
        "../sample"
      )
    ).to eq("relative.rb")
  end

  it "expands relative candidates from the spec directory" do
    integration = described_class.new

    expect(
      integration.send(:relative_candidates, "spec/models/sample_spec.rb", "../support/helper")
    ).to eq(
      [
        File.expand_path("../support/helper", "spec/models"),
        File.expand_path("../support/helper.rb", "spec/models")
      ]
    )
  end

  it "expands both plain and ruby candidates from the base path" do
    integration = described_class.new

    expect(
      integration.send(:expand_candidates, "spec/models", "../support/helper")
    ).to eq(
      [
        File.expand_path("../support/helper", "spec/models"),
        File.expand_path("../support/helper.rb", "spec/models")
      ]
    )
  end

  it "includes the spec dir, project dir, and load path for plain require candidates" do
    integration = described_class.new
    original_load_path = $LOAD_PATH.dup

    allow(Dir).to receive(:pwd).and_return("/project")
    $LOAD_PATH.unshift("/ruby/lib", "/gem/lib")

    expect(
      integration.send(:require_candidates, "spec/models/sample_spec.rb", "lib/sample")
    ).to include(
      File.expand_path("lib/sample", "spec/models"),
      File.expand_path("lib/sample", "/project"),
      File.expand_path("lib/sample", "/ruby/lib")
    )
  ensure
    $LOAD_PATH.replace(original_load_path)
  end

  it "writes child stdout and stderr into the combined scenario log" do
    with_temp_workspace do |_dir|
      integration = described_class.new
      log_paths = integration.send(:scenario_log_paths, "mutant-1")
      FileUtils.mkdir_p(File.dirname(log_paths[:stdout_path]))
      File.write(log_paths[:stdout_path], "captured stdout\n")
      File.write(log_paths[:stderr_path], "captured stderr\n")

      result = integration.send(
        :build_result,
        Struct.new(:success?, :exitstatus).new(true, 0),
        log_paths
      )

      expect(File.read(result.log_path)).to eq(result.combined_output)
    end
  end

  it "disables thread exception reporting in the mutant child" do
    mutant = Struct.new(:id).new("mutant-thread")
    integration = described_class.new
    log_paths = {
      stdout_path: "reports/mutation-logs/mutant-thread.stdout.log",
      stderr_path: "reports/mutation-logs/mutant-thread.stderr.log",
      log_path: "reports/mutation-logs/mutant-thread.log"
    }
    log_support = instance_double(Henitai::Integration::ScenarioLogSupport)

    allow(integration).to receive(:scenario_log_support).and_return(log_support)
    allow(log_support).to receive(:with_coverage_dir).with(mutant.id).and_yield
    allow(log_support).to receive(:capture_child_output).with(log_paths).and_yield
    allow(Henitai::Mutant::Activator).to receive(:activate!).with(mutant).and_return(0)
    allow(integration).to receive(:run_tests).with(["spec/foo_spec.rb"]).and_return(0)
    calls = []

    allow(Thread).to receive(:report_on_exception=) { |value| calls << value }

    result = integration.send(
      :run_in_child,
      mutant:,
      test_files: ["spec/foo_spec.rb"],
      log_paths:
    )

    expect([calls, result]).to eq([[false], 0])
  end

  it "returns an empty string when reading a missing log file" do
    integration = described_class.new

    expect(integration.send(:read_log_file, "missing/log.log")).to eq("")
  end

  it "builds baseline log paths under reports/mutation-logs" do
    integration = described_class.new

    expect(integration.send(:scenario_log_paths, "baseline")).to eq(
      stdout_path: "reports/mutation-logs/baseline.stdout.log",
      stderr_path: "reports/mutation-logs/baseline.stderr.log",
      log_path: "reports/mutation-logs/baseline.log"
    )
  end

  it "formats combined logs without empty sections" do
    integration = described_class.new
    expect(
      [
        integration.send(:combined_log, "out\n", ""),
        integration.send(:combined_log, "", "err\n")
      ]
    ).to eq(
      [
        "stdout:\nout\n",
        "stderr:\nerr\n"
      ]
    )
  end

  it "delegates pause to sleep" do
    integration = described_class.new
    calls = []

    allow(integration).to receive(:sleep) { |seconds| calls << seconds }

    integration.send(:pause, 0.25)

    expect(calls).to eq([0.25])
  end
end
