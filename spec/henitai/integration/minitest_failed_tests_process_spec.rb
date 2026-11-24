# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::Integration::Minitest do
  let(:repo_gemfile) { File.expand_path("../../../Gemfile", __dir__) }

  it "writes the killing test file, and only it, as failed_tests in the child report" do
    Dir.mktmpdir do |dir|
      source = write(dir, "lib/sample.rb", "class Sample\n  def self.sum(a, b)\n    a + b\n  end\nend\n")
      killing = write(dir, "test/killing_test.rb", test_source("Killing", "assert_equal 4, Sample.sum(3, 1)"))
      passing = write(dir, "test/passing_test.rb", test_source("Passing", "assert_equal 1, 1"))

      stdout, stderr, status = run_child(dir, source, [killing, passing])

      report = JSON.parse(File.read(Dir.glob(File.join(dir, "reports/mutation-logs/*.report.json")).first))
      expect([status.success?, report.fetch("failed_tests"), JSON.parse(stdout)]).to eq(
        [true, [File.expand_path(killing)], [File.expand_path(killing)]]
      ), [stdout, stderr].reject(&:empty?).join("\n")
    end
  end

  it "starts no further test class after the first failing one" do
    Dir.mktmpdir do |dir|
      source = write(dir, "lib/sample.rb", "class Sample\n  def self.sum(a, b)\n    a + b\n  end\nend\n")
      first = write(dir, "test/first_test.rb", test_source("First", "assert_equal 4, Sample.sum(3, 1)"))
      second = write(dir, "test/second_test.rb", test_source("Second", "assert_equal 4, Sample.sum(2, 2)"))

      stdout, stderr, status = run_child(dir, source, [first, second])

      failed = JSON.parse(stdout) if status.success?
      expect(failed&.size).to eq(1), [stdout, stderr].reject(&:empty?).join("\n")
    end
  end

  it "attributes a test inherited from a shared module to the including test file" do
    Dir.mktmpdir do |dir|
      source = write(dir, "lib/sample.rb", "class Sample\n  def self.sum(a, b)\n    a + b\n  end\nend\n")
      write(dir, "test/shared_examples.rb", shared_source)
      including = write(dir, "test/including_test.rb", including_source)

      stdout, stderr, status = run_child(dir, source, [including])

      expect([status.success?, JSON.parse(stdout)]).to eq([true, [File.expand_path(including)]]), stderr
    end
  end

  it "reports the test file that hangs as hanging_test when the child times out" do
    Dir.mktmpdir do |dir|
      source = write(dir, "lib/sample.rb", "class Sample\n  def self.sum(a, b)\n    a + b\n  end\nend\n")
      passing = write(dir, "test/passing_test.rb", test_source("Passing", "assert_equal 1, 1"))
      hanging = write(dir, "test/hanging_test.rb", test_source("Hanging", "sleep 30"))

      stdout, stderr, status = run_child(dir, source, [passing, hanging], timeout: 2.0, expected_status: :timeout)

      expect([status.success?, JSON.parse(stdout)]).to eq(
        [true, File.expand_path(hanging)]
      ), [stdout, stderr].reject(&:empty?).join("\n")
    end
  end

  def shared_source
    <<~RUBY
      module SharedExamples
        def test_shared
          assert_equal 4, Sample.sum(3, 1)
        end
      end
    RUBY
  end

  def including_source
    <<~RUBY
      require "minitest/autorun"
      require_relative "../lib/sample"
      require_relative "shared_examples"

      class IncludingTest < Minitest::Test
        include SharedExamples
      end
    RUBY
  end

  def write(dir, relative, source)
    path = File.join(dir, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, source)
    path
  end

  def test_source(name, assertion)
    <<~RUBY
      require "minitest/autorun"
      require_relative "../lib/sample"

      class #{name}Test < Minitest::Test
        def test_example
          #{assertion}
        end
      end
    RUBY
  end

  def run_child(dir, source, test_paths, timeout: 20.0, expected_status: :killed)
    script = <<~RUBY
      require "henitai"
      require #{source.dump}
      subject = Henitai::SubjectResolver.new.resolve_from_files([#{source.dump}]).first
      mutant = Henitai::MutantGenerator.new.generate([subject], [Henitai::Operators::ArithmeticOperator.new]).first
      result = Henitai::ProcessWorkerRunner.new(worker_count: 1, flaky_tests: Henitai::FlakyTestRegistry.new([]))
        .run([mutant], Henitai::Integration::Minitest.new, Struct.new(:timeout, :max_flaky_retries).new(#{timeout}, 0),
             nil, test_files: #{test_paths.inspect}).first
      abort(result.status.to_s) unless result.status == #{expected_status.inspect}
      puts JSON.generate(result.status == :timeout ? result.hanging_test : result.killing_tests)
    RUBY
    Open3.capture3({ "BUNDLE_GEMFILE" => repo_gemfile }, "bundle", "exec", "ruby", "-rjson", "-e", script, chdir: dir)
  end
end
