# frozen_string_literal: true

require "fileutils"
require "open3"
require "spec_helper"
require "timeout"
require "tmpdir"

RSpec.describe Henitai::Integration::Rspec do
  before do
    allow(Process).to receive(:setpgid).and_return(0)
    allow(Process).to receive(:kill).and_raise(Errno::ESRCH)
  end

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

  def with_env(key, value)
    original = ENV.fetch(key, nil)
    ENV[key] = value
    yield
  ensure
    if original.nil?
      ENV.delete(key)
    else
      ENV[key] = original
    end
  end

  def repo_gemfile
    File.expand_path("../../../Gemfile", __dir__)
  end

  def real_child_mutant_script(source_path, spec_path)
    <<~RUBY
      require "henitai"

      source_path = #{source_path.dump}
      spec_path = #{spec_path.dump}
      require source_path
      subject = Henitai::SubjectResolver.new.resolve_from_files([source_path]).find do |candidate|
        candidate.expression == "IntegrationRealActivationSample.value"
      end
      mutant = Henitai::MutantGenerator.new.generate(
        [subject],
        [Henitai::Operators::ArithmeticOperator.new]
      ).first
      result = Henitai::Integration::Rspec.new.run_mutant(
        mutant: mutant,
        test_files: [spec_path],
        timeout: 5.0
      )

      abort("unexpected=\#{result.status}\\n\#{result.combined_output}") unless result.killed?

      puts result.status
    RUBY
  end

  def real_child_zero_examples_script(source_path, spec_path)
    <<~RUBY
      require "henitai"

      source_path = #{source_path.dump}
      spec_path = #{spec_path.dump}
      require source_path
      subject = Henitai::SubjectResolver.new.resolve_from_files([source_path]).find do |candidate|
        candidate.expression == "IntegrationRealActivationSample.value"
      end
      mutant = Henitai::MutantGenerator.new.generate(
        [subject],
        [Henitai::Operators::ArithmeticOperator.new]
      ).first
      result = Henitai::Integration::Rspec.new.run_mutant(
        mutant: mutant,
        test_files: [spec_path],
        timeout: 5.0
      )

      zero_examples_output =
        result.combined_output.include?("No examples found.") ||
        result.combined_output.include?("0 examples, 0 failures")

      unless result.status == :compile_error && zero_examples_output
        abort("unexpected=\#{result.status}\\n\#{result.combined_output}")
      end

      puts result.status
    RUBY
  end

  def run_real_child_mutant(dir, source_path, spec_path)
    Open3.capture3(
      { "BUNDLE_GEMFILE" => repo_gemfile },
      "bundle", "exec", "ruby", "-e", real_child_mutant_script(source_path, spec_path),
      chdir: dir
    )
  end

  def run_real_child_zero_examples_mutant(dir, source_path, spec_path)
    Open3.capture3(
      { "BUNDLE_GEMFILE" => repo_gemfile },
      "bundle", "exec", "ruby", "-e", real_child_zero_examples_script(source_path, spec_path),
      chdir: dir
    )
  end

  def run_repo_suite_script(script, spec_path)
    Timeout.timeout(15) do
      Open3.capture3(
        { "BUNDLE_GEMFILE" => repo_gemfile },
        "bundle", "exec", "ruby",
        "-r", "henitai/rspec_coverage_formatter",
        "-e", script,
        spec_path,
        chdir: File.dirname(repo_gemfile)
      )
    end
  end

  def stub_suite_run(integration, pid:, wait_result:, build_result:)
    record = { wait_args: nil, cleanup: [], reap: [] }

    stub_suite_spawn(pid)
    stub_suite_wait(integration, record, wait_result)
    stub_suite_result(integration, build_result)
    stub_suite_cleanup(integration, record)
    stub_suite_reap(integration, record)

    record
  end

  def stub_suite_spawn(pid)
    allow(Process).to receive(:spawn).and_return(pid)
  end

  def stub_suite_wait(integration, record, wait_result)
    allow(integration).to receive(:wait_with_timeout) do |spawned_pid, timeout|
      record[:wait_args] = [spawned_pid, timeout]
      wait_result
    end
  end

  def stub_suite_result(integration, build_result)
    allow(integration).to receive(:build_result).and_return(build_result)
  end

  def stub_suite_cleanup(integration, record)
    allow(integration).to receive(:cleanup_process_group) do |value|
      record[:cleanup] << value
    end
  end

  def stub_suite_reap(integration, record)
    allow(integration).to receive(:reap_child) do |value|
      record[:reap] << value
    end
  end

  def mutant_log_paths(name)
    {
      stdout_path: "reports/mutation-logs/#{name}.stdout.log",
      stderr_path: "reports/mutation-logs/#{name}.stderr.log",
      log_path: "reports/mutation-logs/#{name}.log"
    }
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

  def zero_examples_spec_source
    <<~RUBY
      # Intentionally defines no examples.
      require_relative "../lib/integration_real_activation_sample"
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
    stub_ordered_rspec(order, integration: integration)
    stub_ordered_wait(integration, order)
  end

  def stub_real_activation_run(integration, child_pid:)
    stub_child_logging(integration)
    allow(Process).to receive(:exit)
    allow(Process).to receive(:fork) do |&block|
      block.call
      child_pid
    end
    allow(integration).to receive_messages(run_tests: 0, wait_with_timeout: :survived, build_result: :survived)
    allow(integration).to receive(:cleanup_process_group)
  end

  def real_activation_source
    <<~RUBY
      class IntegrationRealActivationSample
        def self.value(a, b = 1, *rest, c:, d: 2, **kwrest, &block)
          a + b
        end
      end
    RUBY
  end

  def real_activation_spec_source
    <<~RUBY
      require_relative "../lib/integration_real_activation_sample"

      RSpec.describe IntegrationRealActivationSample do
        it "uses the class method" do
          expect(described_class.value(3, c: 4)).to eq(4)
        end
      end
    RUBY
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

  def stub_ordered_rspec(order, integration:)
    allow(integration).to receive(:run_tests) do |test_files|
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
    stub_timeout_boundary_rspec(integration)
    stub_timeout_boundary_pause(integration, record)
    stub_timeout_boundary_wait(record)
    stub_timeout_boundary_clock
    stub_timeout_boundary_status
  end

  def stub_timeout_boundary_exit(record)
    allow(Process).to receive(:exit) { |status| record[:child_status] = status }
  end

  def stub_timeout_boundary_fork(_record)
    allow(Process).to receive(:fork) do |&block|
      block.call
      24_610
    end
  end

  def stub_timeout_boundary_activation
    allow(Henitai::Mutant::Activator).to receive(:activate!).and_return(0)
  end

  def stub_timeout_boundary_rspec(integration)
    allow(integration).to receive(:run_tests).and_return(0)
  end

  def stub_timeout_boundary_pause(_integration, record)
    allow(IO).to receive(:select) do
      record[:selects] += 1
      [[], nil, nil]
    end
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
    allow(Process).to receive_messages(
      last_status: Struct.new(:success?, :exitstatus).new(true, 0)
    )
  end

  it "runs the full suite" do
    integration = described_class.new

    with_temp_workspace do
      calls = { cleanup: [], reap: [] }

      allow(Process).to receive(:spawn).and_return(4321)
      allow(integration).to receive(:wait_with_timeout).and_return(
        Struct.new(:success?, :exitstatus).new(true, 0)
      )
      allow(integration).to receive(:cleanup_process_group) do |pid|
        calls[:cleanup] << pid
      end
      allow(integration).to receive(:reap_child) do |pid|
        calls[:reap] << pid
      end

      result = integration.run_suite(["spec/foo_spec.rb"])

      expect([result, calls]).to eq([
                                      :survived,
                                      {
                                        cleanup: [4321],
                                        reap: []
                                      }
                                    ])
    end
  end

  it "skips suite cleanup when the process never starts" do
    integration = described_class.new

    with_temp_workspace do
      calls = { cleanup: [], reap: [] }

      allow(Process).to receive(:spawn).and_return(nil)
      allow(integration).to receive_messages(
        wait_with_timeout: Struct.new(:success?, :exitstatus).new(true, 0),
        build_result: :survived
      )
      allow(integration).to receive(:cleanup_process_group) do |pid|
        calls[:cleanup] << pid
      end
      allow(integration).to receive(:reap_child) do |pid|
        calls[:reap] << pid
      end

      result = integration.run_suite(["spec/foo_spec.rb"])

      expect([result, calls]).to eq([
                                      :survived,
                                      {
                                        cleanup: [],
                                        reap: []
                                      }
                                    ])
    end
  end

  it "reaps a suite child when the wait result is nil" do
    integration = described_class.new

    with_temp_workspace do
      calls = { cleanup: [], reap: [] }

      allow(Process).to receive(:spawn).and_return(4321)
      allow(integration).to receive_messages(
        wait_with_timeout: nil,
        build_result: :survived
      )
      allow(integration).to receive(:cleanup_process_group) do |pid|
        calls[:cleanup] << pid
      end
      allow(integration).to receive(:reap_child) do |pid|
        calls[:reap] << pid
      end

      result = integration.run_suite(["spec/foo_spec.rb"])

      expect([result, calls]).to eq([
                                      :survived,
                                      {
                                        cleanup: [4321],
                                        reap: [4321]
                                      }
                                    ])
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

  it "creates the baseline mutation log directory before spawning the suite" do
    integration = described_class.new

    with_temp_workspace do
      allow(Process).to receive(:spawn).and_return(4321)
      allow(integration).to receive(:wait_with_timeout).and_return(
        Struct.new(:success?, :exitstatus).new(true, 0)
      )

      allow(FileUtils).to receive(:mkdir_p).and_call_original

      integration.run_suite(["spec/foo_spec.rb"])

      expect(FileUtils).to have_received(:mkdir_p)
        .with("reports/mutation-logs")
        .at_least(:once)
    end
  end

  it "spawns the baseline suite in its own process group" do
    integration = described_class.new

    with_temp_workspace do
      allow(Process).to receive(:spawn).and_return(4321)
      allow(integration).to receive(:wait_with_timeout).and_return(
        Struct.new(:success?, :exitstatus).new(true, 0)
      )

      integration.run_suite(["spec/foo_spec.rb"])

      expect(Process).to have_received(:spawn).with(
        integration.send(:subprocess_env),
        *integration.send(:suite_command, ["spec/foo_spec.rb"]),
        out: kind_of(File),
        err: kind_of(File),
        pgroup: true
      )
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
      calls = stub_suite_run(
        integration,
        pid: 4321,
        wait_result: :timeout,
        build_result: :timeout
      )

      result = integration.run_suite(["spec/foo_spec.rb"], timeout: 12.5)

      expect([result, calls]).to eq([
                                      :timeout,
                                      {
                                        wait_args: [4321, 12.5],
                                        cleanup: [],
                                        reap: []
                                      }
                                    ])
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
      [
        "bundle", "exec", "ruby",
        "-r", "henitai/rspec_coverage_formatter",
        "-e", integration.send(:rspec_suite_runner_script),
        "spec/foo_spec.rb"
      ]
    )
  end

  it "runs the baseline suite runner script against the repo cli spec" do
    integration = described_class.new

    stdout, stderr, status = run_repo_suite_script(
      integration.send(:rspec_suite_runner_script),
      "spec/henitai/cli_spec.rb"
    )

    expect(status.success?).to be(true), [stdout, stderr].reject(&:empty?).join("\n")
  end

  it "enables the no-examples guard for mutant child rspec runs" do
    integration = described_class.new

    allow(RSpec.configuration).to receive(:fail_if_no_examples=)
    allow(integration).to receive(:debug_child_rspec_trace)
    allow(integration).to receive(:debug_child_example_count)
    allow(integration).to receive(:debug_child_puts)
    allow(integration).to receive(:run_rspec_runner).and_return(0)
    integration.send(:run_tests, ["spec/henitai/cli_spec.rb"])

    expect(RSpec.configuration).to have_received(:fail_if_no_examples=).with(true)
  end

  it "sets files_to_run before loading spec files when debug child is enabled" do
    integration = described_class.new

    allow(integration).to receive(:debug_child_puts)
    allow(integration).to receive(:debug_child_example_count)
    allow(RSpec.__send__(:configuration)).to receive(:fail_if_no_examples=)
    allow(RSpec.configuration).to receive(:files_to_run=)
    allow(RSpec.configuration).to receive(:load_spec_files)

    with_env("HENITAI_DEBUG_CHILD", "1") do
      integration.send(:load_rspec_spec_files, ["spec/henitai/cli_spec.rb"])
    end

    expect(RSpec.configuration).to have_received(:files_to_run=).with(
      [File.expand_path("spec/henitai/cli_spec.rb")]
    )
  end

  it "logs the runner invocation lifecycle when debug child is enabled" do
    integration = described_class.new
    messages = []
    runner = instance_double(RSpec::Core::Runner)

    allow(integration).to receive(:debug_child_puts) { |message| messages << message }
    allow(RSpec.__send__(:configuration)).to receive(:fail_if_no_examples=)
    allow(integration).to receive(:debug_child_rspec_trace)
    allow(RSpec::Core::Runner).to receive(:trap_interrupt)
    allow(integration).to receive(:build_rspec_runner).and_return(runner)
    allow(runner).to receive(:send).with(:configure, $stderr, $stdout)
    allow(runner).to receive(:send).with(:run_specs, anything).and_return(0)
    allow(RSpec.configuration).to receive(:files_to_run=)
    allow(RSpec.configuration).to receive(:load_spec_files)

    with_env("HENITAI_DEBUG_CHILD", "1") do
      integration.send(:run_tests, ["spec/henitai/cli_spec.rb"])
    end

    expect(messages).to include(
      "[henitai-debug-child] runner_run_start",
      "[henitai-debug-child] build_rspec_runner_start",
      "[henitai-debug-child] build_rspec_runner_return",
      "[henitai-debug-child] configure_rspec_runner_start",
      "[henitai-debug-child] trap_interrupt_start",
      "[henitai-debug-child] trap_interrupt_return",
      "[henitai-debug-child] runner_configure_start",
      "[henitai-debug-child] runner_configure_return",
      "[henitai-debug-child] configure_rspec_runner_return",
      "[henitai-debug-child] load_spec_files_start",
      "[henitai-debug-child] load_spec_files_return",
      "[henitai-debug-child] run_specs_return result=0",
      "[henitai-debug-child] run_specs_start",
      "[henitai-debug-child] runner_run_ensure",
      a_string_including("[henitai-debug-child] rspec_world_example_count_after_load="),
      "[henitai-debug-child] runner_run_return status=0"
    )
  end

  it "dumps child threads when the runner times out in debug mode" do
    integration = described_class.new
    allow(integration).to receive(:pause)
    allow(integration).to receive(:cleanup_process_group)
    allow(integration).to receive(:reap_child)
    allow(Process).to receive(:kill)

    with_env("HENITAI_DEBUG_CHILD", "1") do
      integration.send(:handle_timeout, 4321)
    end

    expect(Process).to have_received(:kill).with(:USR1, 4321)
  end

  it "logs SystemExit from the runner invocation when debug child is enabled" do
    integration = described_class.new
    messages = []
    raised = nil
    runner = instance_double(RSpec::Core::Runner)

    allow(integration).to receive(:debug_child_puts) { |message| messages << message }
    allow(RSpec.configuration).to receive(:fail_if_no_examples=)
    allow(integration).to receive(:debug_child_rspec_trace)
    allow(RSpec::Core::Runner).to receive(:trap_interrupt)
    allow(integration).to receive(:build_rspec_runner).and_return(runner)
    allow(runner).to receive(:send).with(:configure, $stderr, $stdout)
    allow(RSpec.configuration).to receive(:files_to_run=)
    allow(RSpec.configuration).to receive(:load_spec_files).and_raise(SystemExit.new(2))

    with_env("HENITAI_DEBUG_CHILD", "1") do
      integration.send(:run_tests, ["spec/henitai/cli_spec.rb"])
    rescue SystemExit => e
      raised = e
    end

    expect([raised.class, messages]).to match(
      [
        SystemExit,
        a_collection_including(
          a_string_including("[henitai-debug-child] runner_run_start"),
          a_string_including("[henitai-debug-child] runner_run_system_exit status=2"),
          a_string_including("[henitai-debug-child] runner_run_ensure")
        )
      ]
    )
  end

  it "dumps a thread snapshot when requested in debug mode" do
    integration = described_class.new
    thread = instance_double(Thread, object_id: 123, status: "sleep", backtrace: ["foo.rb:1"])
    messages = []

    allow(integration).to receive(:debug_child_puts) { |message| messages << message }
    allow(Thread).to receive(:list).and_return([thread])

    with_env("HENITAI_DEBUG_CHILD", "1") do
      integration.send(:debug_child_thread_dump, "timeout")
    end

    expect(messages).to include(
      "[henitai-debug-child] thread_dump reason=timeout",
      "[henitai-debug-child] thread index=0 id=123 status=\"sleep\"",
      "[henitai-debug-child]   foo.rb:1"
    )
  end

  it "returns the discovered spec files as test files" do
    integration = described_class.new

    allow(integration).to receive(:spec_files).and_return(["spec/a_spec.rb"])

    expect(integration.test_files).to eq(["spec/a_spec.rb"])
  end

  it "excludes fixture specs listed in .rspec from test discovery" do
    with_temp_workspace do |dir|
      write_file(dir, ".rspec", <<~TEXT)
        --pattern spec/**/*_spec.rb
        --exclude-pattern spec/fixtures/**/*_spec.rb
      TEXT
      write_file(dir, "spec/unit/sample_spec.rb", "")
      write_file(dir, "spec/fixtures/integration_smoke/rspec/spec/greeting_spec.rb", "")

      expect(described_class.new.send(:spec_files)).to eq(["spec/unit/sample_spec.rb"])
    end
  end

  it "memoizes spec file discovery across repeated selection calls" do
    with_temp_workspace do |dir|
      write_file(dir, "spec/sample_spec.rb", sample_spec_source)

      subject = Henitai::Subject.new(
        namespace: "Sample",
        method_name: "value",
        source_location: {
          file: File.join(dir, "lib/sample.rb"),
          range: 1..4
        }
      )
      integration = described_class.new

      allow(Dir).to receive(:glob).and_call_original

      2.times do
        integration.select_tests(subject)
      end

      expect(Dir).to have_received(:glob).with("spec/**/*_spec.rb").once
    end
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
        Struct.new(:success?, :exitstatus).new(true, 0)
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

  it "puts the child in its own process group before activation" do
    mutant = Struct.new(:id).new("mutant-setpgid")
    integration = described_class.new
    record = {}
    original_env = ENV.fetch("HENITAI_MUTANT_ID", nil)

    begin
      stub_child_logging(integration)
      allow(Process).to receive(:exit) { |status| record[:child_status] = status }
      allow(Process).to receive(:fork) do |&block|
        record[:forked] = true
        block.call
        4329
      end
      allow(Process).to receive(:setpgid) do |pid, pgrp|
        record[:setpgid] = [pid, pgrp]
      end
      allow(Henitai::Mutant::Activator).to receive(:activate!).and_return(0)
      allow(integration).to receive(:run_tests).and_return(0)
      allow(Process).to receive(:wait).and_return(4329)
      allow(Process).to receive_messages(
        last_status: Struct.new(:success?, :exitstatus).new(true, 0)
      )

      integration.run_mutant(
        mutant:,
        test_files: ["spec/foo_spec.rb"],
        timeout: 1.5
      )

      expect(record).to include(setpgid: [0, 0])
    ensure
      ENV["HENITAI_MUTANT_ID"] = original_env
    end
  end

  it "uses the mutant id when building mutant log paths" do
    mutant = Struct.new(:id).new("abc")
    integration = described_class.new
    log_paths = mutant_log_paths("mutant-abc")
    record = { names: [], cleanup: [], reap: [] }

    stub_child_logging(integration)
    allow(Process).to receive(:exit)
    allow(Process).to receive(:fork) do |&block|
      block.call
      4321
    end
    allow(Henitai::Mutant::Activator).to receive(:activate!).and_return(0)
    allow(integration).to receive(:run_tests).and_return(0)
    allow(integration).to receive_messages(
      wait_with_timeout: Struct.new(:success?, :exitstatus).new(true, 0),
      build_result: :survived
    )
    allow(integration).to receive(:scenario_log_paths) do |name|
      record[:names] << name
      log_paths
    end
    allow(integration).to receive(:cleanup_process_group) do |pid|
      record[:cleanup] << pid
    end
    allow(integration).to receive(:reap_child) do |pid|
      record[:reap] << pid
    end

    result = integration.run_mutant(mutant:, test_files: ["spec/foo_spec.rb"], timeout: 1.5)

    expect([result, record]).to eq([
                                     :survived,
                                     {
                                       names: ["mutant-abc"],
                                       cleanup: [4321],
                                       reap: []
                                     }
                                   ])
  end

  it "cleans up the mutant process group after a successful run" do
    mutant = Struct.new(:id).new("mutant-1a")
    integration = described_class.new
    record = { signals: [] }
    original_env = ENV.fetch("HENITAI_MUTANT_ID", nil)

    begin
      stub_child_logging(integration)
      allow(Process).to receive(:exit) { |status| record[:child_status] = status }
      allow(Process).to receive(:fork) do |&block|
        record[:forked] = true
        block.call
        4322
      end
      allow(Henitai::Mutant::Activator).to receive(:activate!).and_return(0)
      allow(integration).to receive(:run_tests).and_return(0)
      allow(Process).to receive(:wait).and_return(4322)
      allow(Process).to receive_messages(
        last_status: Struct.new(:success?, :exitstatus).new(true, 0)
      )
      allow(Process).to receive(:kill) do |signal, pid|
        record[:signals] << [signal, pid]
        raise Errno::ESRCH if signal == :SIGKILL
      end

      integration.run_mutant(mutant:, test_files: ["spec/foo_spec.rb"], timeout: 1.5)

      expect(record).to eq(
        child_status: 0,
        forked: true,
        signals: [
          [:SIGTERM, -4322],
          [:SIGKILL, -4322]
        ]
      )
    ensure
      ENV["HENITAI_MUTANT_ID"] = original_env
    end
  end

  it "reports a survived result after a successful run" do
    mutant = Struct.new(:id).new("mutant-1a")
    integration = described_class.new
    record = { signals: [] }
    original_env = ENV.fetch("HENITAI_MUTANT_ID", nil)

    begin
      stub_child_logging(integration)
      allow(Process).to receive(:exit) { |status| record[:child_status] = status }
      allow(Process).to receive(:fork) do |&block|
        record[:forked] = true
        block.call
        4322
      end
      allow(Henitai::Mutant::Activator).to receive(:activate!).and_return(0)
      allow(integration).to receive(:run_tests).and_return(0)
      allow(Process).to receive(:wait).and_return(4322)
      allow(Process).to receive_messages(
        last_status: Struct.new(:success?, :exitstatus).new(true, 0)
      )
      allow(Process).to receive(:kill) do |signal, pid|
        record[:signals] << [signal, pid]
        raise Errno::ESRCH if signal == :SIGKILL
      end

      result = integration.run_mutant(mutant:, test_files: ["spec/foo_spec.rb"], timeout: 1.5)

      expect(result.status).to eq(:survived)
    ensure
      ENV["HENITAI_MUTANT_ID"] = original_env
    end
  end

  it "skips mutant cleanup when fork does not return a pid" do
    mutant = Struct.new(:id).new("mutant-nil-pid")
    integration = described_class.new
    record = { cleanup: [], reap: [] }
    original_env = ENV.fetch("HENITAI_MUTANT_ID", nil)

    begin
      stub_child_logging(integration)
      allow(Process).to receive(:exit)
      allow(Process).to receive(:fork) do |&block|
        block.call
        nil
      end
      allow(Henitai::Mutant::Activator).to receive(:activate!).and_return(0)
      allow(integration).to receive(:run_tests).and_return(0)
      allow(integration).to receive_messages(
        wait_with_timeout: Struct.new(:success?, :exitstatus).new(true, 0),
        build_result: :survived
      )
      allow(integration).to receive(:cleanup_process_group) do |pid|
        record[:cleanup] << pid
      end
      allow(integration).to receive(:reap_child) do |pid|
        record[:reap] << pid
      end

      result = integration.run_mutant(
        mutant:,
        test_files: ["spec/foo_spec.rb"],
        timeout: 1.5
      )

      expect([result, record]).to eq([
                                       :survived,
                                       {
                                         cleanup: [],
                                         reap: []
                                       }
                                     ])
    ensure
      ENV["HENITAI_MUTANT_ID"] = original_env
    end
  end

  it "reaps a mutant child when the wait result is nil" do
    mutant = Struct.new(:id).new("mutant-nil-wait")
    integration = described_class.new
    record = { cleanup: [], reap: [] }
    original_env = ENV.fetch("HENITAI_MUTANT_ID", nil)

    begin
      stub_child_logging(integration)
      allow(Process).to receive(:exit)
      allow(Process).to receive(:fork) do |&block|
        block.call
        4323
      end
      allow(Henitai::Mutant::Activator).to receive(:activate!).and_return(0)
      allow(integration).to receive(:run_tests).and_return(0)
      allow(integration).to receive_messages(
        wait_with_timeout: nil,
        build_result: :survived
      )
      allow(integration).to receive(:cleanup_process_group) do |pid|
        record[:cleanup] << pid
      end
      allow(integration).to receive(:reap_child) do |pid|
        record[:reap] << pid
      end

      result = integration.run_mutant(
        mutant:,
        test_files: ["spec/foo_spec.rb"],
        timeout: 1.5
      )

      expect([result, record]).to eq([
                                       :survived,
                                       {
                                         cleanup: [4323],
                                         reap: [4323]
                                       }
                                     ])
    ensure
      ENV["HENITAI_MUTANT_ID"] = original_env
    end
  end

  it "does not clean up a mutant child when the wait times out" do
    mutant = Struct.new(:id).new("mutant-timeout")
    integration = described_class.new
    record = { cleanup: [], reap: [] }
    original_env = ENV.fetch("HENITAI_MUTANT_ID", nil)

    begin
      stub_child_logging(integration)
      allow(Process).to receive(:exit)
      allow(Process).to receive(:fork) do |&block|
        block.call
        4324
      end
      allow(Henitai::Mutant::Activator).to receive(:activate!).and_return(0)
      allow(integration).to receive(:run_tests).and_return(0)
      allow(integration).to receive_messages(
        wait_with_timeout: :timeout,
        build_result: :timeout
      )
      allow(integration).to receive(:cleanup_process_group) do |pid|
        record[:cleanup] << pid
      end
      allow(integration).to receive(:reap_child) do |pid|
        record[:reap] << pid
      end

      result = integration.run_mutant(
        mutant:,
        test_files: ["spec/foo_spec.rb"],
        timeout: 1.5
      )

      expect([result, record]).to eq([
                                       :timeout,
                                       {
                                         cleanup: [],
                                         reap: []
                                       }
                                     ])
    ensure
      ENV["HENITAI_MUTANT_ID"] = original_env
    end
  end

  it "falls back to the child pid when process-group cleanup is not permitted" do
    integration = described_class.new
    record = { signals: [] }

    allow(Process).to receive(:getpgid).with(4322).and_return(4322)
    allow(Process).to receive(:kill) do |signal, pid|
      record[:signals] << [signal, pid]
      raise Errno::EPERM if pid.negative?
    end
    allow(integration).to receive(:pause)

    integration.cleanup_process_group(4322)

    expect(record[:signals]).to eq(
      [[:SIGTERM, -4322], [:SIGTERM, 4322], [:SIGKILL, 4322]]
    )
  end

  it "waits for child exit with a wakeup select" do
    integration = described_class.new
    wait_status = Struct.new(:success?, :exitstatus).new(true, 0)
    select_calls = 0

    allow(Process).to receive(:wait).with(4321, Process::WNOHANG).and_return(nil, 4321)
    allow(Process).to receive(:last_status).and_return(wait_status)
    allow(IO).to receive(:select) do
      select_calls += 1
      [[], nil, nil]
    end

    result = integration.send(:wait_with_timeout, 4321, 1.0)

    expect([result, select_calls]).to eq([wait_status, 1])
  end

  it "skips SIGKILL when the child exits during cleanup" do
    integration = described_class.new
    record = { signals: [] }
    select_calls = 0

    allow(Process).to receive(:wait).with(4322, Process::WNOHANG).and_return(nil, 4322)
    allow(Process).to receive(:kill) do |signal, pid|
      record[:signals] << [signal, pid]
    end
    allow(IO).to receive(:select) do
      select_calls += 1
      [[], nil, nil]
    end

    integration.cleanup_process_group(4322)

    expect([record[:signals], select_calls]).to eq([[[:SIGTERM, -4322]], 1])
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
          [:rspec, ["spec/bar_spec.rb"]],
          [:exit, 0],
          [:wait, 9876, 2.0]
        ]
      )
    ensure
      ENV["HENITAI_MUTANT_ID"] = original_env
    end
  end

  it "activates a real class-method mutant through the public integration API" do
    with_temp_workspace do |dir|
      source_path = write_file(dir, "lib/integration_real_activation_sample.rb", real_activation_source)
      spec_path = write_file(
        dir,
        "spec/integration_real_activation_sample_spec.rb",
        real_activation_spec_source
      )

      subject = Henitai::SubjectResolver.new.resolve_from_files([source_path]).find do |candidate|
        candidate.expression == "IntegrationRealActivationSample.value"
      end
      mutant = Henitai::MutantGenerator.new.generate(
        [subject],
        [Henitai::Operators::ArithmeticOperator.new]
      ).first
      integration = described_class.new
      original_env = ENV.fetch("HENITAI_MUTANT_ID", nil)

      begin
        stub_real_activation_run(integration, child_pid: 12_345)

        integration.run_mutant(
          mutant:,
          test_files: [spec_path],
          timeout: 1.5
        )

        expect(IntegrationRealActivationSample.value(3, c: 4)).to eq(2)
      ensure
        ENV["HENITAI_MUTANT_ID"] = original_env
      end
    end
  end

  it "kills a real mutant through the forked child RSpec run" do
    with_temp_workspace do |dir|
      source_path = write_file(dir, "lib/integration_real_activation_sample.rb", real_activation_source)
      spec_path = write_file(
        dir,
        "spec/integration_real_activation_sample_spec.rb",
        real_activation_spec_source
      )
      stdout, stderr, status = run_real_child_mutant(dir, source_path, spec_path)

      summary = [stdout, stderr].reject(&:empty?).join("\n")

      expect(status.success? && stdout.include?("killed")).to be(true), summary
    end
  end

  it "classifies a real zero-example mutant child run as compile_error (non-survived)" do
    with_temp_workspace do |dir|
      source_path = write_file(dir, "lib/integration_real_activation_sample.rb", real_activation_source)
      spec_path = write_file(
        dir,
        "spec/zero_examples_spec.rb",
        zero_examples_spec_source
      )

      stdout, stderr, status = run_real_child_zero_examples_mutant(dir, source_path, spec_path)

      summary = [stdout, stderr].reject(&:empty?).join("\n")

      expect(status.success? && stdout.include?("compile_error")).to be(true), summary
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
      allow(integration).to receive_messages(pause: nil, run_tests: 0)
      allow(Process).to receive(:wait).and_return(24_601)
      allow(Process).to receive_messages(last_status: Struct.new(:success?, :exitstatus).new(true, 0))

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
      allow(integration).to receive_messages(pause: nil, run_tests: 1)
      allow(Process).to receive(:wait).and_return(24_602)
      allow(Process).to receive_messages(last_status: Struct.new(:success?, :exitstatus).new(false, 1))

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
      allow(integration).to receive(:run_tests) do |_files|
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
    record = { selects: 0 }
    original_env = ENV.fetch("HENITAI_MUTANT_ID", nil)

    begin
      stub_child_logging(integration)
      allow(Process).to receive(:exit) { |status| record[:child_status] = status }
      allow(Process).to receive(:fork) do |&block|
        block.call
        24_603
      end
      allow(Henitai::Mutant::Activator).to receive(:activate!).and_return(0)
      allow(integration).to receive(:run_tests).and_return(0)
      allow(integration).to receive(:cleanup_process_group)
      allow(Process).to receive(:wait).and_return(nil, 24_603)
      allow(IO).to receive(:select) do
        record[:selects] += 1
        [[], nil, nil]
      end
      allow(Process).to receive_messages(
        last_status: Struct.new(:success?, :exitstatus).new(true, 0)
      )

      integration.run_mutant(
        mutant:,
        test_files: ["spec/pending_spec.rb"],
        timeout: 0.1
      )

      expect(record).to include(
        selects: 1,
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
        signals: array_including([:SIGTERM, -2468], [:SIGKILL, -2468]),
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
        signals: array_including([:SIGTERM, -2469], [:SIGKILL, -2469]),
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
    record = { waits: 0, selects: 0 }
    original_env = ENV.fetch("HENITAI_MUTANT_ID", nil)

    begin
      stub_timeout_boundary_run(integration, record)

      result = integration.run_mutant(
        mutant:,
        test_files: ["spec/pending_spec.rb"],
        timeout: 0.1
      )

      expect([result.status, record]).to eq(
        [
          :survived,
          {
            waits: 3,
            selects: 1,
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
        last_status: Struct.new(:success?, :exitstatus).new(false, 1)
      )
      allow(Henitai::Mutant::Activator).to receive(:activate!).and_return(0)
      allow(integration).to receive(:pause).and_return(nil)
      allow(integration).to receive(:run_tests) do |files|
        record[:rspec_files] = files
        1
      end

      integration.run_mutant(
        mutant:,
        test_files: ["spec/failing_spec.rb"],
        timeout: 0.1
      )

      expect(record).to include(
        rspec_files: [
          "spec/failing_spec.rb"
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
    allow(Henitai::Mutant::Activator).to receive(:activation_source_for).with(mutant).and_return("source")
    allow(Henitai::Mutant::Activator).to receive(:activate!).with(mutant).and_return(0)
    allow(integration).to receive(:run_tests).with(["spec/foo_spec.rb"]).and_return(0)
    allow(integration).to receive(:suppress_simplecov!)
    allow(integration).to receive(:suppress_coverage!)
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

  it "suppresses SimpleCov during mutant child runs" do
    mutant = Struct.new(:id).new("mutant-simplecov")
    integration = described_class.new
    log_paths = {
      stdout_path: "reports/mutation-logs/mutant-simplecov.stdout.log",
      stderr_path: "reports/mutation-logs/mutant-simplecov.stderr.log",
      log_path: "reports/mutation-logs/mutant-simplecov.log"
    }
    log_support = instance_double(Henitai::Integration::ScenarioLogSupport)

    allow(integration).to receive_messages(
      scenario_log_support: log_support,
      suppress_simplecov!: nil
    )
    allow(log_support).to receive(:with_coverage_dir).with(mutant.id).and_yield
    allow(log_support).to receive(:capture_child_output).with(log_paths).and_yield
    allow(Henitai::Mutant::Activator).to receive(:activation_source_for).with(mutant).and_return("source")
    allow(Henitai::Mutant::Activator).to receive(:activate!).with(mutant).and_return(0)
    allow(integration).to receive(:run_tests).with(["spec/foo_spec.rb"]).and_return(0)
    allow(integration).to receive(:suppress_coverage!)

    integration.send(
      :run_in_child,
      mutant:,
      test_files: ["spec/foo_spec.rb"],
      log_paths:
    )

    expect(integration).to have_received(:suppress_simplecov!)
  end

  it "forces single-worker parallel env inside the mutant child" do
    mutant = Struct.new(:id).new("mutant-parallel-env")
    integration = described_class.new
    log_paths = {
      stdout_path: "reports/mutation-logs/mutant-parallel-env.stdout.log",
      stderr_path: "reports/mutation-logs/mutant-parallel-env.stderr.log",
      log_path: "reports/mutation-logs/mutant-parallel-env.log"
    }
    log_support = instance_double(Henitai::Integration::ScenarioLogSupport)
    original_parallel_workers = ENV.fetch("PARALLEL_WORKERS", nil)
    observed_parallel_workers = nil

    allow(integration).to receive(:scenario_log_support).and_return(log_support)
    allow(log_support).to receive(:with_coverage_dir).with(mutant.id).and_yield
    allow(log_support).to receive(:capture_child_output).with(log_paths).and_yield
    allow(Henitai::Mutant::Activator).to receive(:activation_source_for).with(mutant).and_return("source")
    allow(Henitai::Mutant::Activator).to receive(:activate!).with(mutant).and_return(0)
    allow(integration).to receive(:run_tests).with(["spec/foo_spec.rb"]) do
      observed_parallel_workers = ENV.fetch("PARALLEL_WORKERS", nil)
      0
    end

    integration.send(
      :run_in_child,
      mutant:,
      test_files: ["spec/foo_spec.rb"],
      log_paths:
    )

    expect(observed_parallel_workers).to eq("1")
  ensure
    if original_parallel_workers.nil?
      ENV.delete("PARALLEL_WORKERS")
    else
      ENV["PARALLEL_WORKERS"] = original_parallel_workers
    end
  end

  it "captures child diagnostics after output redirection starts" do
    mutant = Struct.new(:id).new("mutant-debug")
    integration = described_class.new
    log_paths = {
      stdout_path: "reports/mutation-logs/mutant-debug.stdout.log",
      stderr_path: "reports/mutation-logs/mutant-debug.stderr.log",
      log_path: "reports/mutation-logs/mutant-debug.log"
    }
    log_support = instance_double(Henitai::Integration::ScenarioLogSupport)
    capture_started = false

    allow(integration).to receive(:scenario_log_support).and_return(log_support)
    allow(log_support).to receive(:with_coverage_dir).with(mutant.id).and_yield
    allow(log_support).to receive(:capture_child_output).with(log_paths) do |_paths, &block|
      capture_started = true
      block.call
    end
    allow(Henitai::Mutant::Activator).to receive(:activation_source_for).with(mutant).and_return("source")
    allow(Henitai::Mutant::Activator).to receive(:activate!).with(mutant).and_return(0)
    allow(integration).to receive(:run_tests).with(["spec/foo_spec.rb"]).and_return(0)
    allow(integration).to receive(:suppress_simplecov!)
    allow(integration).to receive(:suppress_coverage!)
    allow(integration).to receive(:debug_child_puts) do |_message|
      raise "debug output before capture" unless capture_started
    end

    with_env("HENITAI_DEBUG_CHILD", "1") do
      integration.send(
        :run_in_child,
        mutant:,
        test_files: ["spec/foo_spec.rb"],
        log_paths:
      )
    end

    expect(capture_started).to be(true)
  end

  it "includes loaded feature diagnostics when debug child is enabled" do
    integration = described_class.new
    expanded_spec = File.expand_path("spec/foo_spec.rb")
    original_features = $LOADED_FEATURES.dup
    messages = []

    $LOADED_FEATURES << expanded_spec
    allow(integration).to receive(:debug_child_puts) { |message| messages << message }

    with_env("HENITAI_DEBUG_CHILD", "1") do
      integration.send(
        :debug_child_rspec_trace,
        test_files: ["spec/foo_spec.rb"],
        rspec_options: [],
        rspec_argv: ["spec/foo_spec.rb"]
      )
    end

    expect(
      messages.any? { |message| message.include?("loaded_features_check=[[\"spec/foo_spec.rb\", true]]") }
    ).to be(true)
  ensure
    $LOADED_FEATURES.replace(original_features)
  end

  it "includes example count diagnostics when debug child is enabled" do
    integration = described_class.new
    messages = []
    world = instance_double(RSpec::Core::World)

    allow(integration).to receive(:debug_child_puts) { |message| messages << message }
    allow(RSpec).to receive(:world).and_return(world)
    allow(world).to receive(:example_count).and_return(3, 5)

    with_env("HENITAI_DEBUG_CHILD", "1") do
      integration.send(:debug_child_example_count, "before_run")
      integration.send(:debug_child_example_count, "after_run")
    end

    expect(messages).to include(
      "[henitai-debug-child] rspec_world_example_count_before_run=3",
      "[henitai-debug-child] rspec_world_example_count_after_run=5"
    )
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

  describe "#spawn_mutant" do
    it "returns a ChildHandle with a pid and log_paths" do
      mutant = Struct.new(:id).new("mutant-spawn-1")
      integration = described_class.new
      original_env = ENV.fetch("HENITAI_MUTANT_ID", nil)

      begin
        stub_child_logging(integration)
        allow(Process).to receive(:exit)
        allow(Henitai::Mutant::Activator).to receive(:activate!).and_return(0)
        allow(integration).to receive(:run_tests).and_return(0)
        allow(Process).to receive(:fork) do |&block|
          block.call
          55_555
        end

        handle = integration.spawn_mutant(mutant:, test_files: ["spec/foo_spec.rb"])

        expect([handle.pid, handle.log_paths.keys]).to eq(
          [55_555, %i[stdout_path stderr_path log_path]]
        )
      ensure
        ENV["HENITAI_MUTANT_ID"] = original_env
      end
    end

    it "forks exactly one child that calls run_in_child with no exec boundary" do
      # Contract test: mutation activation and test execution must share the
      # same forked child process. This is the same-process activation contract
      # documented in docs/postmortem-2026-04-24-rspec-execution-regression.md.
      #
      # spawn_mutant must call Process.fork exactly once. The block passed to
      # fork must call run_in_child (not spawn/system/exec). We verify this by
      # ensuring fork is called exactly once and no additional subprocess
      # boundary is introduced.
      mutant = Struct.new(:id).new("mutant-spawn-contract")
      integration = described_class.new
      record = { fork_count: 0 }
      original_env = ENV.fetch("HENITAI_MUTANT_ID", nil)

      begin
        stub_child_logging(integration)
        allow(Process).to receive(:exit)
        allow(Henitai::Mutant::Activator).to receive(:activate!).and_return(0)
        allow(integration).to receive(:run_tests).and_return(0)
        allow(Process).to receive(:fork) do |&block|
          record[:fork_count] += 1
          block.call
          99_999
        end

        integration.spawn_mutant(mutant:, test_files: ["spec/foo_spec.rb"])

        expect(record[:fork_count]).to eq(1)
      ensure
        ENV["HENITAI_MUTANT_ID"] = original_env
      end
    end

    it "returns a ChildHandle with log_paths matching the mutant id" do
      mutant = Struct.new(:id).new("mutant-spawn-paths")
      integration = described_class.new
      original_env = ENV.fetch("HENITAI_MUTANT_ID", nil)

      begin
        allow(Process).to receive(:fork).and_return(77_777)

        handle = integration.spawn_mutant(mutant:, test_files: ["spec/foo_spec.rb"])

        expect(handle.log_paths.values_at(:stdout_path, :stderr_path)).to all(
          include("mutant-mutant-spawn-paths")
        )
      ensure
        ENV["HENITAI_MUTANT_ID"] = original_env
      end
    end
  end

  describe "Integration::Base#spawn_mutant" do
    it "raises NotImplementedError on the base class" do
      integration = Henitai::Integration::Base.new

      expect do
        integration.spawn_mutant(mutant: nil, test_files: [])
      end.to raise_error(NotImplementedError)
    end
  end

  describe "Integration::ChildHandle" do
    it "is a struct with pid and log_paths keyword arguments" do
      handle = Henitai::Integration::ChildHandle.new(
        pid: 42,
        log_paths: { stdout_path: "/tmp/out.log", stderr_path: "/tmp/err.log" }
      )

      expect([handle.pid, handle.log_paths[:stdout_path]]).to eq([42, "/tmp/out.log"])
    end
  end
end
