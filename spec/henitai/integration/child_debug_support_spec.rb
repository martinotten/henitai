# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Integration::ChildDebugSupport do
  # The methods in this module are included via Integration::Base, and Coverage
  # gem does not track lines executed on anonymous objects created with
  # Object.new.extend. Tests must exercise the methods through a concrete class
  # that includes the module so per-test coverage data is collected on the
  # source lines.

  let(:integration) { Henitai::Integration::Rspec.new }
  let(:messages) { [] }

  before { allow(integration).to receive(:debug_child_puts) { |msg| messages << msg } }

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

  describe "#debug_child?" do
    it "returns true when HENITAI_DEBUG_CHILD is set to 1" do
      with_debug_child("1") { expect(integration.send(:debug_child?)).to be(true) }
    end

    it "returns false when HENITAI_DEBUG_CHILD is not set" do
      with_debug_child(nil) { expect(integration.send(:debug_child?)).to be(false) }
    end

    it "returns false when HENITAI_DEBUG_CHILD is not 1" do
      with_debug_child("0") { expect(integration.send(:debug_child?)).to be(false) }
    end
  end

  describe "#debug_child_puts" do
    before { allow(integration).to receive(:debug_child_puts).and_call_original }

    it "writes the message to stdout and flushes it", :aggregate_failures do
      allow($stdout).to receive(:puts)
      allow($stdout).to receive(:flush)

      integration.send(:debug_child_puts, "hello")

      expect($stdout).to have_received(:puts).with("hello")
      expect($stdout).to have_received(:flush)
    end
  end

  describe "#debug_child_rspec_trace" do
    let(:test_files) { ["spec/existing_spec.rb", "spec/missing_spec.rb"] }

    before do
      allow(File).to receive(:exist?).with("spec/existing_spec.rb").and_return(true)
      allow(File).to receive(:exist?).with("spec/missing_spec.rb").and_return(false)
      allow(integration).to receive(:loaded_feature_map).and_return([["spec/existing_spec.rb", true]])
    end

    it "does nothing when debug mode is off" do
      with_debug_child(nil) do
        integration.send(
          :debug_child_rspec_trace,
          test_files: test_files,
          rspec_options: %w[--seed 1],
          rspec_argv: %w[spec]
        )
      end

      expect(messages).to be_empty
    end

    it "logs cwd, file existence, loaded features, and argv when debug mode is on" do
      with_debug_child("1") do
        integration.send(
          :debug_child_rspec_trace,
          test_files: test_files,
          rspec_options: %w[--seed 1],
          rspec_argv: %w[spec]
        )
      end

      expect(messages.join("\n")).to eq(
        "[henitai-debug-child] cwd=#{Dir.pwd}\n" \
        "[henitai-debug-child] files_exist=#{[['spec/existing_spec.rb', true],
                                              ['spec/missing_spec.rb', false]].inspect}\n" \
        "[henitai-debug-child] loaded_features_check=#{[['spec/existing_spec.rb', true]].inspect}\n" \
        "[henitai-debug-child] test_files=#{test_files.inspect}\n" \
        "[henitai-debug-child] rspec_options=#{%w[--seed 1].inspect}\n" \
        "[henitai-debug-child] rspec_argv=#{%w[spec].inspect}"
      )
    end

    it "calls #inspect (not #to_s) on the loaded_feature_map result" do
      fake_map = Object.new
      def fake_map.inspect = "INSPECTED-MAP"
      def fake_map.to_s = "TOSTRING-MAP"
      allow(integration).to receive(:loaded_feature_map).and_return(fake_map)

      with_debug_child("1") do
        integration.send(
          :debug_child_rspec_trace,
          test_files: test_files,
          rspec_options: %w[--seed 1],
          rspec_argv: %w[spec]
        )
      end

      expect(messages.join("\n")).to include("loaded_features_check=INSPECTED-MAP")
    end
  end

  describe "#debug_child_rspec_exit" do
    it "does nothing when debug mode is off" do
      with_debug_child(nil) { integration.send(:debug_child_rspec_exit, 0) }

      expect(messages).to be_empty
    end

    it "logs the exact result string when debug mode is on" do
      with_debug_child("1") { integration.send(:debug_child_rspec_exit, 0) }

      expect(messages).to eq(["[henitai-debug-child] RSpec result=#{0.inspect}"])
    end
  end

  describe "#debug_child_example_count" do
    before do
      world = instance_double(RSpec::Core::World, example_count: 7)
      allow(RSpec).to receive(:__send__).with(:world).and_return(world)
    end

    it "does not log when debug mode is off" do
      with_debug_child(nil) { integration.send(:debug_child_example_count, "before_run") }

      expect(messages).to be_empty
    end

    it "logs example count when debug mode is on" do
      with_debug_child("1") { integration.send(:debug_child_example_count, "before_run") }

      expect(messages).to eq(["[henitai-debug-child] rspec_world_example_count_before_run=7"])
    end
  end

  describe "#debug_child_activation_start" do
    it "does nothing when debug mode is off" do
      with_debug_child(nil) { integration.send(:debug_child_activation_start, "mutant-1") }

      expect(messages).to be_empty
    end

    it "logs the mutant id when debug mode is on" do
      with_debug_child("1") { integration.send(:debug_child_activation_start, "mutant-1") }

      expect(messages).to eq(["[henitai-debug-child] activate_start mutant=mutant-1"])
    end
  end

  describe "#debug_child_activation_end" do
    it "does nothing when debug mode is off" do
      with_debug_child(nil) do
        integration.send(:debug_child_activation_end, :ok, test_files: ["spec/a_spec.rb"])
      end

      expect(messages).to be_empty
    end

    it "logs the activation result and test files when debug mode is on" do
      with_debug_child("1") do
        integration.send(:debug_child_activation_end, :ok, test_files: ["spec/a_spec.rb"])
      end

      expect(messages).to eq(
        [
          "[henitai-debug-child] activate_end result=#{:ok.inspect}\n" \
          "[henitai-debug-child] run_tests_start test_files=#{['spec/a_spec.rb'].inspect}"
        ]
      )
    end
  end

  describe "#debug_child_mutant_meta" do
    let(:full_mutant) do
      subject = instance_double(Henitai::Subject, expression: "x > 0")
      instance_double(
        Henitai::Mutant,
        stable_id: "abc123",
        operator: "ArithmeticOperator",
        subject: subject,
        location: "lib/foo.rb:1"
      )
    end

    it "reports nil for every field when the mutant responds to nothing" do
      bare_mutant = Object.new

      integration.send(:debug_child_mutant_meta, bare_mutant)

      expect(messages).to eq(
        [
          "[henitai-debug-child] mutant_meta stableId=\n" \
          "[henitai-debug-child] mutant_meta operator=\n" \
          "[henitai-debug-child] mutant_meta subject=\n" \
          "[henitai-debug-child] mutant_meta location=\n"
        ]
      )
    end

    it "reports the real values when the mutant responds to everything" do
      integration.send(:debug_child_mutant_meta, full_mutant)

      expect(messages).to eq(
        [
          "[henitai-debug-child] mutant_meta stableId=abc123\n" \
          "[henitai-debug-child] mutant_meta operator=ArithmeticOperator\n" \
          "[henitai-debug-child] mutant_meta subject=x > 0\n" \
          "[henitai-debug-child] mutant_meta location=#{'lib/foo.rb:1'.inspect}\n"
        ]
      )
    end

    it "reports nil subject expression when subject does not respond to expression" do
      mutant = instance_double(
        Henitai::Mutant,
        stable_id: "abc123",
        operator: "ArithmeticOperator",
        subject: Object.new,
        location: "lib/foo.rb:1"
      )

      integration.send(:debug_child_mutant_meta, mutant)

      expect(messages.first).to include("mutant_meta subject=\n")
    end
  end

  describe "#debug_child_activation_check" do
    it "logs the resolve_subjects source location as path:line" do
      integration.send(:debug_child_activation_check)

      expected_location = Henitai::Runner.instance_method(:resolve_subjects).source_location.join(":")
      expect(messages).to eq(
        ["[henitai-debug-child] activation_check resolve_subjects_location=#{expected_location}\n"]
      )
    end

    it "logs nil location when resolving the source location raises" do
      allow(Henitai::Runner).to receive(:instance_method).and_raise(StandardError, "boom")

      integration.send(:debug_child_activation_check)

      expect(messages).to eq(
        ["[henitai-debug-child] activation_check resolve_subjects_location=\n"]
      )
    end
  end

  describe "#loaded_feature_map" do
    it "pairs each file with its loaded_feature? result" do
      allow(integration).to receive(:loaded_feature?).with("a.rb").and_return(true)
      allow(integration).to receive(:loaded_feature?).with("b.rb").and_return(false)

      result = integration.send(:loaded_feature_map, ["a.rb", "b.rb"])

      expect(result).to eq([["a.rb", true], ["b.rb", false]])
    end
  end

  describe "#loaded_feature?" do
    let(:original_loaded_features) { $LOADED_FEATURES.dup }

    before { $LOADED_FEATURES.clear }

    after do
      $LOADED_FEATURES.replace(original_loaded_features)
    end

    it "matches when a feature entry is expanded in $LOADED_FEATURES" do
      target_path = File.expand_path("spec/foo_spec.rb")
      $LOADED_FEATURES << target_path

      result = integration.send(:loaded_feature?, "spec/foo_spec.rb")
      expect(result).to be(true)
    end

    it "matches when a feature entry is raw in $LOADED_FEATURES" do
      $LOADED_FEATURES << "spec/foo_spec.rb"

      result = integration.send(:loaded_feature?, "spec/foo_spec.rb")
      expect(result).to be(true)
    end

    it "returns false when no candidate matches" do
      expect(integration.send(:loaded_feature?, "nonexistent/file.rb")).to be(false)
    end

    it "handles an expanded path passed as file argument" do
      target_path = File.expand_path("spec/foo_spec.rb")
      $LOADED_FEATURES << target_path

      result = integration.send(:loaded_feature?, target_path)
      expect(result).to be(true)
    end

    it "handles a .rb-suffixed candidate built from the raw file argument" do
      base = "/tmp/dummy_loaded_feature_test"
      $LOADED_FEATURES << "#{base}.rb"

      result = integration.send(:loaded_feature?, base)
      expect(result).to be(true)
    end

    it "handles a .rb-suffixed candidate built from the expanded file argument" do
      base = "dummy_loaded_feature_expanded"
      $LOADED_FEATURES << "#{File.expand_path(base)}.rb"

      result = integration.send(:loaded_feature?, base)
      expect(result).to be(true)
    end

    it "matches via the normalized candidate only, when the raw feature string matches no candidate" do
      file = "spec/other_file_spec"
      feature = "totally/unrelated/path.rb"
      $LOADED_FEATURES << feature
      allow(File).to receive(:expand_path).and_call_original
      allow(File).to receive(:expand_path).with(feature).and_return(File.expand_path(file))

      result = integration.send(:loaded_feature?, file)
      expect(result).to be(true)
    end

    it "matches via the raw feature only, when the normalized candidate matches no candidate" do
      file = "spec/real_file_spec"
      feature = "#{file}.rb"
      $LOADED_FEATURES << feature
      allow(File).to receive(:expand_path).and_call_original
      allow(File).to receive(:expand_path).with(feature).and_return("/nowhere/unrelated.rb")

      result = integration.send(:loaded_feature?, file)
      expect(result).to be(true)
    end

    it "falls back to the raw feature string without raising when File.expand_path fails on a loaded feature" do
      bad_feature = "spec/broken_spec.rb"
      $LOADED_FEATURES << bad_feature

      allow(File).to receive(:expand_path).and_call_original
      allow(File).to receive(:expand_path).with(bad_feature).and_raise(ArgumentError, "invalid byte sequence")

      expect(integration.send(:loaded_feature?, "spec/broken_spec")).to be(true)
    end
  end

  describe "#rspec_world_example_count" do
    it "returns the world's example count" do
      world = instance_double(RSpec::Core::World, example_count: 42)
      allow(RSpec).to receive(:__send__).with(:world).and_return(world)

      expect(integration.send(:rspec_world_example_count)).to eq(42)
    end

    it "returns nil when RSpec raises an error" do
      allow(RSpec).to receive(:__send__).with(:world).and_raise(StandardError, "rspec not loaded")

      expect(integration.send(:rspec_world_example_count)).to be_nil
    end
  end
end
