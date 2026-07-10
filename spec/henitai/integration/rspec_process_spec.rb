# frozen_string_literal: true

require "fileutils"
require "open3"
require "spec_helper"
require "timeout"
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

  def repo_gemfile
    File.expand_path("../../../Gemfile", __dir__)
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

  def zero_examples_spec_source
    <<~RUBY
      # Intentionally defines no examples.
      require_relative "../lib/integration_real_activation_sample"
    RUBY
  end

  def real_child_script(source_path, spec_path, expected_status)
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
      expected_output = #{expected_status.inspect} != :compile_error || zero_examples_output

      unless result.status == #{expected_status.inspect} && expected_output
        abort("unexpected=\#{result.status}\\n\#{result.combined_output}")
      end

      puts result.status
    RUBY
  end

  def run_real_child(dir, source_path, spec_path, expected_status)
    Open3.capture3(
      { "BUNDLE_GEMFILE" => repo_gemfile },
      "bundle", "exec", "ruby", "-e",
      real_child_script(source_path, spec_path, expected_status),
      chdir: dir
    )
  end

  it "runs the baseline suite runner script against a minimal rspec fixture" do
    integration = described_class.new

    with_temp_workspace do |dir|
      spec_path = write_file(
        dir,
        "spec/smoke_spec.rb",
        <<~RUBY
          RSpec.describe "suite runner" do
            it "passes" do
              expect(1).to eq(1)
            end
          end
        RUBY
      )

      stdout, stderr, status = Timeout.timeout(15) do
        Open3.capture3(
          { "BUNDLE_GEMFILE" => repo_gemfile },
          "bundle", "exec", "ruby",
          "-r", "henitai/rspec_coverage_formatter",
          "-e", integration.rspec_suite_runner_script,
          spec_path,
          chdir: dir
        )
      end

      expect(status.success?).to be(true), [stdout, stderr].reject(&:empty?).join("\n")
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
      stdout, stderr, status = run_real_child(dir, source_path, spec_path, :killed)

      expect(status.success? && stdout.include?("killed")).to be(true), stderr
    end
  end

  it "classifies a real zero-example mutant child run as compile_error" do
    with_temp_workspace do |dir|
      source_path = write_file(dir, "lib/integration_real_activation_sample.rb", real_activation_source)
      spec_path = write_file(dir, "spec/zero_examples_spec.rb", zero_examples_spec_source)
      stdout, stderr, status = run_real_child(dir, source_path, spec_path, :compile_error)

      expect(status.success? && stdout.include?("compile_error")).to be(true), stderr
    end
  end
end
