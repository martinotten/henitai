# frozen_string_literal: true

require "rspec/core"
require "rspec/core/sandbox"
require "spec_helper"
require "stringio"
require "tmpdir"

# The runner's only production caller is a forked mutant child, whose coverage
# never merges into the parent's report. These examples therefore drive the
# real collaborator in-process: every nested RSpec run happens against a
# throwaway world and configuration (RSpec::Core::Sandbox), so it can neither
# see nor disturb this suite's own examples.
RSpec.describe Henitai::Integration::RspecChildRunner do
  subject(:runner) { described_class.new(log: child_log) }

  let(:debug_output) { StringIO.new }
  let(:child_log) { Henitai::Integration::ChildDebugLog.new(io: debug_output) }
  let(:debug_messages) { debug_output.string.split("\n").map { |line| line.delete_prefix(debug_prefix) } }
  let(:debug_prefix) { "[henitai-debug-child] " }

  def a_runner = described_class.new(log: child_log)

  # RspecPreload#preload_environment disables SimpleCov and Coverage in
  # whatever process it runs in. That is correct inside a fork-server child but
  # would replace this suite's own coverage result, so it is stubbed here — as
  # in every other in-process spec (see spec/infra/shared_coverage_process_spec).
  before do
    allow(Henitai::Integration::CoverageRuntimeSuppressors).to receive_messages(
      suppress_simplecov!: nil, suppress_coverage!: nil
    )
  end

  # Runs the block with a fresh RSpec world and configuration and captures its
  # output. Clear SPEC_OPTS so the outer suite's options cannot override a
  # fixture project's .rspec. Restore the INT trap and preload's worker setting.
  def with_child_rspec_world(&block)
    captured = StringIO.new
    original_streams = [$stdout, $stderr]
    previous_int_handler = Signal.trap("INT", "DEFAULT")
    previous_spec_opts = ENV.delete("SPEC_OPTS")
    previous_parallel_workers = ENV.fetch("PARALLEL_WORKERS", nil)
    $stdout = captured
    $stderr = captured
    result, configuration = sandboxed_run(&block)
    [result, configuration, captured.string]
  ensure
    $stdout, $stderr = original_streams
    Signal.trap("INT", previous_int_handler) if previous_int_handler
    set_env("SPEC_OPTS", previous_spec_opts)
    set_env("PARALLEL_WORKERS", previous_parallel_workers)
  end

  def with_env(key, value)
    original = ENV.fetch(key, nil)
    set_env(key, value)
    yield
  ensure
    set_env(key, original)
  end

  def set_env(key, value)
    value.nil? ? ENV.delete(key) : ENV[key] = value
  end

  def sandboxed_run
    result = nil
    configuration = nil
    RSpec::Core::Sandbox.sandboxed do |sandboxed_configuration|
      configuration = sandboxed_configuration
      result = yield
    end
    [result, configuration]
  end

  def write_spec(dir, name, source)
    File.join(dir, name).tap { |path| File.write(path, source) }
  end

  # The tags of the recording specs that actually ran, in run order.
  def ran_tags(marker)
    File.exist?(marker) ? File.read(marker).split : []
  end

  # A spec file with one example that appends its tag to +marker+ when it runs.
  def recording_spec(description, marker, tag)
    <<~RUBY
      RSpec.describe #{description.inspect} do
        it("runs") { File.write(#{marker.dump}, "#{tag}\\n", mode: "a") }
      end
    RUBY
  end

  def failing_spec(description)
    <<~RUBY
      RSpec.describe #{description.inspect} do
        it("fails") { expect(1).to eq(2) }
      end
    RUBY
  end

  def with_debug_child
    original = ENV.fetch("HENITAI_DEBUG_CHILD", nil)
    ENV["HENITAI_DEBUG_CHILD"] = "1"
    yield
  ensure
    original.nil? ? ENV.delete("HENITAI_DEBUG_CHILD") : ENV["HENITAI_DEBUG_CHILD"] = original
  end

  # Every phase the run logs, in order. The debug log is the child's only
  # diagnostic when a mutant child hangs or dies before it reports.
  def expected_trace
    %w[
      build_rspec_runner_start build_rspec_runner_return
      configure_rspec_runner_start trap_interrupt_start trap_interrupt_return
      runner_configure_start runner_configure_return configure_rspec_runner_return
      load_spec_files_start load_spec_files_return
      run_specs_start
    ] + ["run_specs_return result=0", "runner_run_ensure"]
  end

  describe "#run" do
    it "returns 0 when every loaded example passes" do
      Dir.mktmpdir do |dir|
        spec = write_spec(dir, "passing_spec.rb", recording_spec("child runner pass", File.join(dir, "ran"), "a"))

        status, = with_child_rspec_world { runner.run([spec]) }

        expect(status).to eq(0)
      end
    end

    it "returns 1 when an example fails" do
      Dir.mktmpdir do |dir|
        spec = write_spec(dir, "failing_spec.rb", failing_spec("child runner failure"))

        status, = with_child_rspec_world { runner.run([spec]) }

        expect(status).to eq(1)
      end
    end

    # The child would otherwise keep whatever INT handler the parent's fork
    # left in place, and Ctrl-C would not stop it the way a user expects.
    it "installs RSpec's own INT handler instead of leaving the inherited one" do
      Dir.mktmpdir do |dir|
        spec = write_spec(dir, "passing_spec.rb", recording_spec("child runner interrupt", File.join(dir, "ran"), "a"))

        handler, = with_child_rspec_world do
          runner.run([spec])
          # Read the handler back without invoking it.
          Signal.trap("INT", "DEFAULT")
        end

        expect(handler).to be_a(Proc)
      end
    end

    # Without `configure` RSpec keeps the default formatter, so a project's
    # `.rspec --format documentation` never takes effect in the child.
    it "lets RSpec's own .rspec options choose the child's formatter" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, ".rspec"), "--format documentation\n")
        spec = write_spec(dir, "passing_spec.rb", recording_spec("child runner formatter", File.join(dir, "ran"), "a"))

        with_env("SPEC_OPTS", "--format progress") do
          _, _, output = with_child_rspec_world do
            Dir.chdir(dir) { runner.run([spec]) }
          end

          expect([output.lines.first(3), ENV.fetch("SPEC_OPTS", nil)])
            .to eq([["\n", "child runner formatter\n", "  runs\n"], "--format progress"])
        end
      end
    end

    it "runs the after-load hook once the spec files are loaded and before any example runs" do
      Dir.mktmpdir do |dir|
        marker = File.join(dir, "ran")
        spec = write_spec(dir, "passing_spec.rb", recording_spec("child runner hook", marker, "a"))
        at_hook = nil

        with_child_rspec_world do
          runner.run([spec]) do
            at_hook = [RSpec.world.example_groups.size, ran_tags(marker)]
            true
          end
        end

        expect(at_hook).to eq([1, []])
      end
    end

    it "skips the run when the after-load hook returns false, as a failed activation does" do
      Dir.mktmpdir do |dir|
        marker = File.join(dir, "ran")
        spec = write_spec(dir, "passing_spec.rb", recording_spec("child runner skipped", marker, "a"))

        status, = with_child_rspec_world { runner.run([spec]) { false } }

        expect([status, ran_tags(marker)]).to eq([1, []])
      end
    end

    it "does not run the after-load hook when a spec file fails to load" do
      Dir.mktmpdir do |dir|
        spec = write_spec(dir, "broken_spec.rb", %(raise "load boom"\n))
        hook_calls = []

        status, = with_child_rspec_world { runner.run([spec]) { hook_calls << :called } }

        expect([status, hook_calls]).to eq([1, []])
      end
    end

    it "returns 1 without running examples when RSpec wants to quit" do
      Dir.mktmpdir do |dir|
        marker = File.join(dir, "ran")
        spec = write_spec(
          dir, "quitting_spec.rb",
          "RSpec.world.wants_to_quit = true\n#{recording_spec('child runner quitting', marker, 'a')}"
        )

        status, = with_child_rspec_world { runner.run([spec]) }

        expect([status, ran_tags(marker)]).to eq([1, []])
      end
    end

    it "returns 1 without running examples when RSpec is already quitting" do
      Dir.mktmpdir do |dir|
        marker = File.join(dir, "ran")
        spec = write_spec(
          dir, "quitting_spec.rb",
          "RSpec.world.rspec_is_quitting = true\n#{recording_spec('child runner already quitting', marker, 'a')}"
        )

        status, = with_child_rspec_world { runner.run([spec]) }

        expect([status, ran_tags(marker)]).to eq([1, []])
      end
    end

    it "forces fail-fast on, so a project's own setting cannot keep the run going" do
      Dir.mktmpdir do |dir|
        marker = File.join(dir, "ran")
        first = write_spec(
          dir, "first_spec.rb",
          "RSpec.configure { |config| config.fail_fast = false }\n#{failing_spec('child runner first')}"
        )
        second = write_spec(dir, "second_spec.rb", recording_spec("child runner second", marker, "b"))

        status, configuration, = with_child_rspec_world { runner.run([first, second]) }

        expect([status, configuration.fail_fast, ran_tags(marker)]).to eq([1, 1, []])
      end
    end

    it "runs the files in the order it was given, not in RSpec's global order" do
      Dir.mktmpdir do |dir|
        marker = File.join(dir, "ran")
        first = write_spec(dir, "a_spec.rb", recording_spec("child runner ordered a", marker, "a"))
        second = write_spec(dir, "b_spec.rb", recording_spec("child runner ordered b", marker, "b"))

        with_child_rspec_world do
          RSpec.configuration.register_ordering(:global, &:reverse)
          runner.run([second, first])
        end

        expect(ran_tags(marker)).to eq(%w[b a])
      end
    end

    it "re-raises a SystemExit from the loaded spec files and logs it" do
      Dir.mktmpdir do |dir|
        spec = write_spec(dir, "exit_spec.rb", <<~RUBY)
          RSpec.describe "child runner system exit" do
            it("exits") { exit(3) }
          end
        RUBY
        raised_status = nil

        with_debug_child do
          with_child_rspec_world do
            runner.run([spec])
          rescue SystemExit => e
            raised_status = e.status
          end
        end

        expect([raised_status, debug_messages.grep(/runner_run_(?:system_exit|ensure)/)]).to eq(
          [3, ["runner_run_system_exit status=3", "runner_run_ensure"]]
        )
      end
    end

    it "traces every phase of the run through the child debug log" do
      Dir.mktmpdir do |dir|
        spec = write_spec(dir, "passing_spec.rb", recording_spec("child runner traced", File.join(dir, "ran"), "a"))

        with_debug_child { with_child_rspec_world { runner.run([spec]) } }

        expect(debug_messages.grep(/start|return|ensure/)).to eq(expected_trace)
      end
    end

    it "records the loaded example count between loading the spec files and running them" do
      Dir.mktmpdir do |dir|
        first = write_spec(dir, "a_spec.rb", recording_spec("child runner counted a", File.join(dir, "ran"), "a"))
        second = write_spec(dir, "b_spec.rb", recording_spec("child runner counted b", File.join(dir, "ran"), "b"))

        with_debug_child { with_child_rspec_world { runner.run([first, second]) } }

        expect(debug_messages.grep(/example_count/)).to eq(["rspec_world_example_count_after_load=2"])
      end
    end

    it "hands RSpec absolute paths, so a later chdir cannot change what runs" do
      Dir.mktmpdir do |dir|
        write_spec(dir, "passing_spec.rb", recording_spec("child runner relative", File.join(dir, "ran"), "a"))

        _, configuration, = with_child_rspec_world do
          Dir.chdir(dir) { runner.run(["passing_spec.rb"]) }
        end

        expect(configuration.files_to_run).to eq([File.realpath(File.join(dir, "passing_spec.rb"))])
      end
    end

    context "with a runner a fork server already booted" do
      it "runs only the example groups defined in the requested files" do
        Dir.mktmpdir do |dir|
          marker = File.join(dir, "ran")
          wanted = write_spec(dir, "b_spec.rb", recording_spec("child runner preloaded b", marker, "b"))
          other = write_spec(dir, "a_spec.rb", recording_spec("child runner preloaded a", marker, "a"))

          with_child_rspec_world do
            booted = a_runner.preload([other, wanted])
            booted.run([wanted])
          end

          expect(ran_tags(marker)).to eq(%w[b])
        end
      end

      it "keeps the requested file order for the groups it keeps" do
        Dir.mktmpdir do |dir|
          marker = File.join(dir, "ran")
          first = write_spec(dir, "a_spec.rb", recording_spec("child runner preload order a", marker, "a"))
          second = write_spec(dir, "b_spec.rb", recording_spec("child runner preload order b", marker, "b"))

          with_child_rspec_world do
            booted = a_runner.preload([first, second])
            booted.run([second, first])
          end

          expect(ran_tags(marker)).to eq(%w[b a])
        end
      end

      it "knows it was booted, while a fresh runner does not" do
        preloaded_states, = with_child_rspec_world do
          booted = runner.preload([])
          [booted.preloaded?, runner.preloaded?]
        end

        expect(preloaded_states).to eq([true, false])
      end
    end
  end

  describe "#preload" do
    it "returns a preloaded runner holding the loaded example groups" do
      Dir.mktmpdir do |dir|
        spec = write_spec(dir, "passing_spec.rb", recording_spec("child runner boot", File.join(dir, "ran"), "a"))
        booted = nil
        groups = nil

        with_child_rspec_world do
          booted = a_runner.preload([spec])
          groups = RSpec.world.example_groups.size
        end

        expect([booted.class, booted.preloaded?, groups])
          .to eq([described_class::Preloaded, true, 1])
      end
    end

    it "raises PreloadError when a spec file fails to load" do
      Dir.mktmpdir do |dir|
        spec = write_spec(dir, "broken_spec.rb", %(raise "load boom"\n))
        raised = nil

        with_child_rspec_world do
          a_runner.preload([spec])
        rescue Henitai::Integration::RspecChildRunner::PreloadError => e
          raised = e.message
        end

        expect(raised).to eq("the spec files failed to load")
      end
    end
  end

  describe "#rspec_loaded_cleanly?" do
    it "is true once every spec file loaded" do
      Dir.mktmpdir do |dir|
        spec = write_spec(dir, "passing_spec.rb", recording_spec("child runner loaded", File.join(dir, "ran"), "a"))
        boot = a_runner

        loaded, = with_child_rspec_world do
          boot.preload([spec])
          boot.rspec_loaded_cleanly?
        end

        expect(loaded).to be(true)
      end
    end

    it "is false when RSpec wants to quit" do
      loaded, = with_child_rspec_world do
        RSpec.world.wants_to_quit = true
        runner.rspec_loaded_cleanly?
      end

      expect(loaded).to be(false)
    end

    it "is false when RSpec is quitting" do
      loaded, = with_child_rspec_world do
        RSpec.world.rspec_is_quitting = true
        runner.rspec_loaded_cleanly?
      end

      expect(loaded).to be(false)
    end
  end

  # The fork server boots the environment once and hands the loaded runner to
  # every forked mutant process (ADR-15); it must not run a single test itself.
  describe "the fork-server boot" do
    subject(:integration) { Henitai::Integration::Rspec.new }

    [nil, "sentinel"].each do |original|
      it "restores PARALLEL_WORKERS after preload when it was #{original.nil? ? 'unset' : 'set'}" do
        with_env("PARALLEL_WORKERS", original) do
          with_child_rspec_world { integration.preload_environment([]) }

          expect(ENV.fetch("PARALLEL_WORKERS", nil)).to eq(original)
        end
      end
    end

    it "loads the spec files without running a single example" do
      Dir.mktmpdir do |dir|
        marker = File.join(dir, "ran")
        spec = write_spec(dir, "passing_spec.rb", recording_spec("preload boot", marker, "a"))
        groups = nil

        with_child_rspec_world do
          integration.preload_environment([spec])
          groups = RSpec.world.example_groups.size
        end

        expect([groups, ran_tags(marker)]).to eq([1, []])
      end
    end

    it "raises PreloadError when a spec file fails to load" do
      Dir.mktmpdir do |dir|
        spec = write_spec(dir, "broken_spec.rb", %(raise "load boom"\n))
        raised = nil

        with_child_rspec_world do
          integration.preload_environment([spec])
        rescue Henitai::Integration::RspecPreload::PreloadError => e
          raised = e.message
        end

        expect(raised).to eq("the spec files failed to load")
      end
    end
  end
end
