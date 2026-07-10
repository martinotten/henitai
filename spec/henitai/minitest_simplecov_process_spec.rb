# frozen_string_literal: true

require "json"
require "spec_helper"
require "tmpdir"

# minitest_simplecov.rb starts Coverage and SimpleCov at require time, so it is
# exercised in a clean subprocess to avoid disturbing this suite's own coverage
# run. The subprocess reports observable state back as JSON on stdout.
# rubocop:disable RSpec/DescribeClass
RSpec.describe "Minitest SimpleCov bootstrap" do
  # Fences the JSON payload so SimpleCov's own stdout chatter can be stripped.
  def loader_script
    lib = File.expand_path("../../lib", __dir__)
    <<~RUBY
      $LOAD_PATH.unshift #{lib.inspect}
      require "henitai/minitest_simplecov"
      require "json"
      puts "<<<JSON" + JSON.generate(
        coverage_running: Coverage.running?,
        coverage_dir: SimpleCov.coverage_dir
      ) + "JSON>>>"
    RUBY
  end

  def run_loader(coverage_dir_env)
    # A nil value unsets HENITAI_COVERAGE_DIR in the child so the default case is
    # isolated from an inherited env (e.g. when run inside henitai's own coverage
    # bootstrap). chdir: avoids mutating this process's working directory.
    env = { "HENITAI_COVERAGE_DIR" => coverage_dir_env }
    Dir.mktmpdir do |dir|
      out = IO.popen(env, ["ruby", "-e", loader_script], chdir: dir, &:read)
      JSON.parse(out[/<<<JSON(.*)JSON>>>/m, 1])
    end
  end

  it "activates Ruby Coverage tracking on load" do
    expect(run_loader(nil).fetch("coverage_running")).to be(true)
  end

  it "honors HENITAI_COVERAGE_DIR for the SimpleCov output directory" do
    result = run_loader("custom-coverage")

    expect(result.fetch("coverage_dir")).to end_with("custom-coverage")
  end

  it "defaults the coverage directory to coverage when the env var is unset" do
    result = run_loader(nil)

    expect(result.fetch("coverage_dir")).to eq("coverage")
  end
end
# rubocop:enable RSpec/DescribeClass
