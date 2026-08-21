# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Henitai::Integration::ChildDebugLog do
  subject(:log) { described_class.new(io: io, loaded_features: loaded_features) }

  let(:io) { StringIO.new }
  let(:loaded_features) { instance_double(Henitai::Integration::LoadedFeatures, map: []) }
  let(:lines) { io.string.split("\n") }

  def with_debug_child(value)
    original = ENV.fetch("HENITAI_DEBUG_CHILD", nil)
    if value.nil?
      ENV.delete("HENITAI_DEBUG_CHILD")
    else
      ENV["HENITAI_DEBUG_CHILD"] = value
    end
    yield
  ensure
    if original.nil?
      ENV.delete("HENITAI_DEBUG_CHILD")
    else
      ENV["HENITAI_DEBUG_CHILD"] = original
    end
  end

  describe "#enabled?" do
    it "is true when HENITAI_DEBUG_CHILD is exactly 1" do
      with_debug_child("1") { expect(log.enabled?).to be(true) }
    end

    it "is false when HENITAI_DEBUG_CHILD is unset" do
      with_debug_child(nil) { expect(log.enabled?).to be(false) }
    end

    it "is false for any other value" do
      with_debug_child("0") { expect(log.enabled?).to be(false) }
    end
  end

  describe "#write" do
    it "writes the message and flushes when enabled", :aggregate_failures do
      allow(io).to receive(:flush)

      with_debug_child("1") { log.write("hello") }

      expect(io.string).to eq("hello\n")
      expect(io).to have_received(:flush)
    end

    it "stays silent when disabled so unguarded callers cannot leak into child logs" do
      with_debug_child(nil) { log.write("hello") }

      expect(io.string).to be_empty
    end

    # The child reassigns $stdout *after* this object is built (see
    # ScenarioLogSupport#capture_child_output), so a stream captured in
    # #initialize would send every debug line to the parent's terminal
    # instead of the child's log file. Nothing in the smoke suite catches
    # that. `output(...).to_stdout` cannot express it either: it needs
    # construction and the write to see two *different* $stdout objects.
    # rubocop:disable RSpec/ExpectOutput
    it "resolves $stdout per call, not at construction", :aggregate_failures do
      original = $stdout
      at_construction = StringIO.new
      after_redirect = StringIO.new

      begin
        $stdout = at_construction
        default_log = described_class.new
        $stdout = after_redirect
        with_debug_child("1") { default_log.write("late") }
      ensure
        $stdout = original
      end

      expect(at_construction.string).to be_empty
      expect(after_redirect.string).to eq("late\n")
    end
    # rubocop:enable RSpec/ExpectOutput
  end

  describe "#rspec_trace" do
    let(:test_files) { ["spec/existing_spec.rb", "spec/missing_spec.rb"] }

    before do
      allow(File).to receive(:exist?).with("spec/existing_spec.rb").and_return(true)
      allow(File).to receive(:exist?).with("spec/missing_spec.rb").and_return(false)
      allow(loaded_features).to receive(:map).and_return([["spec/existing_spec.rb", true]])
    end

    def trace
      log.rspec_trace(test_files: test_files, rspec_options: %w[--seed 1], rspec_argv: %w[spec])
    end

    # The early return is not merely an optimisation to assert away: without
    # it, every disabled child still stats each test file and walks
    # $LOADED_FEATURES on the hot path.
    it "writes nothing and does no work when disabled", :aggregate_failures do
      with_debug_child(nil) { trace }

      expect(io.string).to be_empty
      expect(loaded_features).not_to have_received(:map)
      expect(File).not_to have_received(:exist?)
    end

    it "logs cwd, file existence, loaded features, options and argv when enabled" do
      with_debug_child("1") { trace }

      expect(io.string).to eq(
        "[henitai-debug-child] cwd=#{Dir.pwd}\n" \
        "[henitai-debug-child] files_exist=#{[['spec/existing_spec.rb', true],
                                              ['spec/missing_spec.rb', false]].inspect}\n" \
        "[henitai-debug-child] loaded_features_check=#{[['spec/existing_spec.rb', true]].inspect}\n" \
        "[henitai-debug-child] test_files=#{test_files.inspect}\n" \
        "[henitai-debug-child] rspec_options=#{%w[--seed 1].inspect}\n" \
        "[henitai-debug-child] rspec_argv=#{%w[spec].inspect}\n"
      )
    end

    it "calls #inspect, not #to_s, on the loaded-features map" do
      map = Object.new
      def map.inspect = "INSPECTED-MAP"
      def map.to_s = "TOSTRING-MAP"
      allow(loaded_features).to receive(:map).and_return(map)

      with_debug_child("1") { trace }

      expect(io.string).to include("loaded_features_check=INSPECTED-MAP")
    end

    it "asks the injected LoadedFeatures about exactly the test files" do
      with_debug_child("1") { trace }

      expect(loaded_features).to have_received(:map).with(test_files)
    end
  end

  describe "#rspec_exit" do
    it "writes nothing when disabled" do
      with_debug_child(nil) { log.rspec_exit(0) }

      expect(io.string).to be_empty
    end

    it "logs the inspected status when enabled" do
      with_debug_child("1") { log.rspec_exit(0) }

      expect(lines).to eq(["[henitai-debug-child] RSpec result=#{0.inspect}"])
    end
  end

  describe "#example_count" do
    before do
      world = instance_double(RSpec::Core::World, example_count: 7)
      allow(RSpec).to receive(:world).and_return(world)
    end

    it "writes nothing and never asks RSpec when disabled", :aggregate_failures do
      with_debug_child(nil) { log.example_count("before_run") }

      expect(io.string).to be_empty
      expect(RSpec).not_to have_received(:world)
    end

    it "labels the count with the stage when enabled" do
      with_debug_child("1") { log.example_count("before_run") }

      expect(lines).to eq(["[henitai-debug-child] rspec_world_example_count_before_run=7"])
    end
  end

  describe "#activation_start" do
    it "writes nothing when disabled" do
      with_debug_child(nil) { log.activation_start("mutant-1") }

      expect(io.string).to be_empty
    end

    it "logs the mutant id when enabled" do
      with_debug_child("1") { log.activation_start("mutant-1") }

      expect(lines).to eq(["[henitai-debug-child] activate_start mutant=mutant-1"])
    end
  end

  describe "#activation_end" do
    it "writes nothing when disabled" do
      with_debug_child(nil) { log.activation_end(:ok, test_files: ["spec/a_spec.rb"]) }

      expect(io.string).to be_empty
    end

    it "logs the activation result and the test files when enabled" do
      with_debug_child("1") { log.activation_end(:ok, test_files: ["spec/a_spec.rb"]) }

      expect(lines).to eq(
        [
          "[henitai-debug-child] activate_end result=#{:ok.inspect}",
          "[henitai-debug-child] run_tests_start test_files=#{['spec/a_spec.rb'].inspect}"
        ]
      )
    end
  end

  describe "#mutant_meta" do
    # Asserting the mutant is never interrogated, not just that nothing was
    # written: #write gates internally, so an output-only assertion would pass
    # with the early return deleted.
    it "writes nothing and never interrogates the mutant when disabled", :aggregate_failures do
      mutant = instance_double(
        Henitai::Mutant, stable_id: "abc123", operator: "op", subject: nil, location: nil
      )

      with_debug_child(nil) { log.mutant_meta(mutant) }

      expect(io.string).to be_empty
      expect(mutant).not_to have_received(:stable_id)
    end

    it "reports every field as empty when the mutant responds to nothing" do
      with_debug_child("1") { log.mutant_meta(Object.new) }

      expect(lines).to eq(
        [
          "[henitai-debug-child] mutant_meta stableId=",
          "[henitai-debug-child] mutant_meta operator=",
          "[henitai-debug-child] mutant_meta subject=",
          "[henitai-debug-child] mutant_meta location="
        ]
      )
    end

    it "reports the real values when the mutant responds to everything" do
      mutant = instance_double(
        Henitai::Mutant,
        stable_id: "abc123",
        operator: "ArithmeticOperator",
        subject: instance_double(Henitai::Subject, expression: "x > 0"),
        location: "lib/foo.rb:1"
      )

      with_debug_child("1") { log.mutant_meta(mutant) }

      expect(lines).to eq(
        [
          "[henitai-debug-child] mutant_meta stableId=abc123",
          "[henitai-debug-child] mutant_meta operator=ArithmeticOperator",
          "[henitai-debug-child] mutant_meta subject=x > 0",
          "[henitai-debug-child] mutant_meta location=#{'lib/foo.rb:1'.inspect}"
        ]
      )
    end

    it "reports an empty subject when the subject does not respond to #expression" do
      mutant = instance_double(
        Henitai::Mutant,
        stable_id: "abc123",
        operator: "ArithmeticOperator",
        subject: Object.new,
        location: "lib/foo.rb:1"
      )

      with_debug_child("1") { log.mutant_meta(mutant) }

      expect(lines).to include("[henitai-debug-child] mutant_meta subject=")
    end
  end

  describe "#activation_check" do
    it "writes nothing and never reflects on Runner when disabled", :aggregate_failures do
      allow(Henitai::Runner).to receive(:instance_method).and_call_original

      with_debug_child(nil) { log.activation_check }

      expect(io.string).to be_empty
      expect(Henitai::Runner).not_to have_received(:instance_method)
    end

    it "logs the resolve_subjects source location as path:line" do
      with_debug_child("1") { log.activation_check }

      expected = Henitai::Runner.instance_method(:resolve_subjects).source_location.join(":")
      expect(lines).to eq(
        ["[henitai-debug-child] activation_check resolve_subjects_location=#{expected}"]
      )
    end

    it "logs an empty location when resolving the source location raises" do
      allow(Henitai::Runner).to receive(:instance_method).and_raise(StandardError, "boom")

      with_debug_child("1") { log.activation_check }

      expect(lines).to eq(["[henitai-debug-child] activation_check resolve_subjects_location="])
    end
  end

  describe "#timeout_signal_sent" do
    it "writes nothing when disabled" do
      with_debug_child(nil) { log.timeout_signal_sent(4321) }

      expect(io.string).to be_empty
    end

    it "logs the signalled pid when enabled" do
      with_debug_child("1") { log.timeout_signal_sent(4321) }

      expect(lines).to eq(["[henitai-debug-child] timeout_signal_sent pid=4321"])
    end
  end

  describe "#thread_dump" do
    it "writes nothing and never walks the thread list when disabled", :aggregate_failures do
      allow(Thread).to receive(:list).and_return([])

      with_debug_child(nil) { log.thread_dump("timeout") }

      expect(io.string).to be_empty
      expect(Thread).not_to have_received(:list)
    end

    it "logs the reason, then one line per thread with its index, id and status" do
      thread = instance_double(Thread, object_id: 99, status: "run", backtrace: nil)
      allow(Thread).to receive(:list).and_return([thread])

      with_debug_child("1") { log.thread_dump("timeout") }

      expect(lines).to eq(
        [
          "[henitai-debug-child] thread_dump reason=timeout",
          "[henitai-debug-child] thread index=0 id=99 status=#{'run'.inspect}"
        ]
      )
    end

    it "indents each backtrace line under its thread" do
      thread = instance_double(Thread, object_id: 99, status: "sleep", backtrace: ["a.rb:1", "b.rb:2"])
      allow(Thread).to receive(:list).and_return([thread])

      with_debug_child("1") { log.thread_dump("timeout") }

      expect(lines.last(2)).to eq(
        ["[henitai-debug-child]   a.rb:1", "[henitai-debug-child]   b.rb:2"]
      )
    end
  end

  describe "#rspec_world_example_count" do
    it "returns the world's example count" do
      world = instance_double(RSpec::Core::World, example_count: 42)
      allow(RSpec).to receive(:world).and_return(world)

      expect(log.rspec_world_example_count).to eq(42)
    end

    it "returns nil when RSpec raises" do
      allow(RSpec).to receive(:world).and_raise(StandardError, "rspec not loaded")

      expect(log.rspec_world_example_count).to be_nil
    end
  end
end
