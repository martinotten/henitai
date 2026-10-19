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

  def run_child(dir, source, test_paths)
    script = <<~RUBY
      require "henitai"
      require #{source.dump}
      subject = Henitai::SubjectResolver.new.resolve_from_files([#{source.dump}]).first
      mutant = Henitai::MutantGenerator.new.generate([subject], [Henitai::Operators::ArithmeticOperator.new]).first
      result = Henitai::Integration::Minitest.new.run_mutant(mutant: mutant, test_files: #{test_paths.inspect}, timeout: 20.0)
      abort(result.status.to_s) unless result.status == :killed
      puts JSON.generate(result.killing_tests)
    RUBY
    Open3.capture3({ "BUNDLE_GEMFILE" => repo_gemfile }, "bundle", "exec", "ruby", "-rjson", "-e", script, chdir: dir)
  end
end
