# frozen_string_literal: true

require "fileutils"
require "open3"
require "spec_helper"
require "tmpdir"

# Regression for EXE-03: a slow suite boot (here a spec_helper that sleeps
# 2.5 s) must count toward the auto-calibrated mutant timeout. Before boot was
# included, the timeout fell to the 2.0 s floor: every run spent its time
# booting, the mutant timed out, the unmutated control run timed out too, and
# ControlRun reclassified the surviving mutant as :compile_error.
RSpec.describe Henitai::ExecutionEngine do
  let(:boot_seconds) { 2.5 }

  def write_file(dir, relative_path, source)
    path = File.join(dir, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, source)
    path
  end

  def write_project(dir, reports_dir)
    write_file(dir, "lib/slow_boot_sample.rb", sample_source)
    write_file(dir, "spec/spec_helper.rb", spec_helper_source)
    write_file(dir, "spec/slow_boot_sample_spec.rb", sample_spec_source)
    write_file(dir, ".henitai.yml", config_source(reports_dir))
  end

  def sample_source
    <<~RUBY
      class SlowBootSample
        def self.value(a, b)
          a + b
        end
      end
    RUBY
  end

  def spec_helper_source
    <<~RUBY
      require "simplecov"

      SimpleCov.coverage_dir(ENV.fetch("HENITAI_COVERAGE_DIR", "coverage"))
      SimpleCov.start { add_filter "/spec/" }

      sleep #{boot_seconds}
    RUBY
  end

  def sample_spec_source
    <<~RUBY
      require "spec_helper"
      require_relative "../lib/slow_boot_sample"

      RSpec.describe SlowBootSample do
        it "calls the subject without asserting anything" do
          described_class.value(1, 2)
        end
      end
    RUBY
  end

  def config_source(reports_dir)
    <<~YAML
      integration:
        name: rspec
      jobs: 1
      reports_dir: #{reports_dir}
      mutation:
        operators: light
    YAML
  end

  # The mutant child is forked from the spec process, so it would inherit this
  # example's RSpec world. The pipeline therefore runs in a fresh Ruby process.
  def pipeline_script
    <<~RUBY
      require "henitai"

      config = Henitai::Configuration.new(path: ".henitai.yml")
      integration = Henitai::Integration::Rspec.new
      integration.run_suite(["spec/slow_boot_sample_spec.rb"])
      source = File.expand_path("lib/slow_boot_sample.rb")
      subject = Henitai::SubjectResolver.new.resolve_from_files([source]).find do |candidate|
        candidate.expression == "SlowBootSample.value"
      end
      mutant = Henitai::MutantGenerator.new.generate(
        [subject],
        [Henitai::Operators::ArithmeticOperator.new]
      ).first
      results = Henitai::ExecutionEngine.new.run([mutant], integration, config)
      puts "STATUS=" + results.map { |result| result.status.to_s }.join(",")
    RUBY
  end

  def run_pipeline(dir, reports_dir)
    Open3.capture3(
      { "BUNDLE_GEMFILE" => repo_gemfile, "HENITAI_REPORTS_DIR" => reports_dir },
      "bundle", "exec", "ruby", "-e", pipeline_script,
      chdir: dir
    )
  end

  def repo_gemfile
    File.expand_path("../../Gemfile", __dir__)
  end

  it "does not time out a surviving mutant when the suite boot is slow", :aggregate_failures do
    Dir.mktmpdir do |dir|
      reports_dir = File.join(dir, "reports")
      write_project(dir, reports_dir)
      stdout, stderr, status = run_pipeline(dir, reports_dir)

      expect(status.success?).to be(true), stderr
      expect(stdout.lines.grep(/\ASTATUS=/).map(&:chomp)).to eq(["STATUS=survived"])
    end
  end
end
