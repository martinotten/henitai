# frozen_string_literal: true

require "json"
require "open3"
require "spec_helper"
require "tmpdir"

# The full suite writes one shared coverage/ result. Code that disables
# SimpleCov in this process, or a child that writes into that directory,
# replaces the suite's own result. These specs run the offending code in clean
# subprocesses so the parent run's coverage stays intact.
# rubocop:disable RSpec/DescribeClass
RSpec.describe "Shared coverage result" do
  let(:root) { File.expand_path("../..", __dir__) }

  def runner_script
    lib = File.join(root, "lib")
    <<~RUBY
      $LOAD_PATH.unshift #{lib.inspect}
      require "json"
      require "simplecov"
      require "minitest"
      Minitest.define_singleton_method(:run) { |_args = []| true }
      require "henitai/integration/minitest_test_runner"
      Henitai::Integration::MinitestTestRunner.new.call([])
      puts JSON.generate(external_at_exit: SimpleCov.external_at_exit)
    RUBY
  end

  it "leaves SimpleCov's at_exit result storage enabled in the parent RSpec process" do
    expect(SimpleCov.external_at_exit).not_to be(true)
  end

  it "keeps SimpleCov storing the calling process's result after a runner call", :aggregate_failures do
    stdout, stderr, status = Dir.mktmpdir do |dir|
      Open3.capture3("ruby", "-e", runner_script, chdir: dir)
    end

    expect(status.success?).to be(true), stderr
    expect(JSON.parse(stdout).fetch("external_at_exit")).not_to be(true)
  end

  it "keeps the dogfood child's coverage out of the caller's coverage directory", :aggregate_failures do
    Dir.mktmpdir do |caller_dir|
      stdout, stderr, status = Open3.capture3(
        { "HENITAI_COVERAGE_DIR" => caller_dir },
        "bundle", "exec", "rake", "smoke:integration:dogfood_rspec",
        chdir: root
      )

      expect(status.success?).to be(true), [stdout, stderr].reject(&:empty?).join("\n")
      expect(File.exist?(File.join(caller_dir, ".resultset.json"))).to be(false)
    end
  end
end
# rubocop:enable RSpec/DescribeClass
