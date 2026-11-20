# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "spec_helper"
require "timeout"
require "tmpdir"

# The execution contract of the one mutant driver (ADR-20), with real
# processes: every combination of slot count and fork server must give the
# same verdicts and leave no child process behind.
RSpec.describe Henitai::ExecutionEngine, "#run" do
  def repo_gemfile
    File.expand_path("../../Gemfile", __dir__)
  end

  def write_file(dir, relative_path, source)
    path = File.join(dir, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, source)
    path
  end

  def write_project(dir)
    write_file(dir, "lib/contract_sample.rb", sample_source)
    write_file(dir, "spec/contract_sample_spec.rb", sample_spec_source)
  end

  def sample_source
    <<~RUBY
      class ContractSample
        def self.total(a, b)
          a + b
        end

        def self.big?(number)
          number > 100
        end
      end
    RUBY
  end

  def sample_spec_source
    <<~RUBY
      require_relative "../lib/contract_sample"

      RSpec.describe ContractSample do
        it("adds") { expect(described_class.total(2, 3)).to eq(5) }
        it("knows a big number") { expect(described_class.big?(500)).to be(true) }
      end
    RUBY
  end

  def contract_script(jobs:, fork_server:)
    <<~RUBY
      require "henitai"

      source = File.expand_path("lib/contract_sample.rb")
      subjects = Henitai::SubjectResolver.new.resolve_from_files([source])
      operators = [Henitai::Operators::ArithmeticOperator.new, Henitai::Operators::EqualityOperator.new]
      mutants = Henitai::MutantGenerator.new.generate(subjects, operators)
      config = Henitai::Configuration.load(
        overrides: { jobs: #{jobs}, mutation: { timeout: 20.0, fork_server: #{fork_server} } }
      )
      Henitai::ExecutionEngine.new.run(mutants, Henitai::Integration::Rspec.new, config)

      leftover = begin
        Process.wait2(-1, Process::WNOHANG) ? "reaped" : "running"
      rescue Errno::ECHILD
        "none"
      end
      verdicts = mutants.to_h { |mutant| ["\#{mutant.subject.expression} \#{mutant.description}", mutant.status] }
      puts JSON.generate("verdicts" => verdicts.sort.to_h, "children" => leftover)
    RUBY
  end

  def run_contract(jobs:, fork_server:)
    Dir.mktmpdir do |dir|
      write_project(dir)
      stdout, stderr, status = Timeout.timeout(120) do
        Open3.capture3({ "BUNDLE_GEMFILE" => repo_gemfile }, "bundle", "exec", "ruby", "-e",
                       contract_script(jobs:, fork_server:), chdir: dir)
      end
      raise "contract run failed:\n#{stdout}\n#{stderr}" unless status.success?

      JSON.parse(stdout.lines.last)
    end
  end

  let(:expected_verdicts) do
    {
      "ContractSample.big? replaced > with !=" => "survived",
      "ContractSample.big? replaced > with <" => "killed",
      "ContractSample.big? replaced > with <=" => "killed",
      "ContractSample.big? replaced > with <=>" => "killed",
      "ContractSample.big? replaced > with ==" => "killed",
      "ContractSample.big? replaced > with >=" => "survived",
      "ContractSample.total replaced + with -" => "killed"
    }
  end

  shared_examples "the mutant driver" do |jobs:, fork_server:|
    it "gives every mutant the same verdict and leaves no child behind (jobs=#{jobs}, fork_server=#{fork_server})",
       :aggregate_failures do
      outcome = run_contract(jobs:, fork_server:)

      expect(outcome["verdicts"]).to eq(expected_verdicts)
      expect(outcome["children"]).to eq("none")
    end
  end

  it_behaves_like "the mutant driver", jobs: 1, fork_server: false
  it_behaves_like "the mutant driver", jobs: 2, fork_server: false
  it_behaves_like "the mutant driver", jobs: 1, fork_server: true
  it_behaves_like "the mutant driver", jobs: 2, fork_server: true
end
