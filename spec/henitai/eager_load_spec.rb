# frozen_string_literal: true

require "json"
require "open3"
require "spec_helper"
require "tmpdir"

# eager_load.rb is a standalone entry point that forces every Henitai constant
# to load (so external mutation tooling can discover subjects via ObjectSpace).
# It is exercised in a clean subprocess because its whole job is the global side
# effect of populating the constant table, which would otherwise leak into this
# suite's own load state. The subprocess reports observable state back as JSON.
# rubocop:disable RSpec/DescribeClass
RSpec.describe "Henitai eager loading" do
  # A sample of constants spread across the autoload table and the nested
  # namespaces that broke under the old filesystem-order glob.
  def sample_constants
    %w[
      Henitai::Runner
      Henitai::Reporter
      Henitai::Integration::Rspec
      Henitai::CLI::CleanCommand
      Henitai::Operators::ArithmeticOperator
      Henitai::Mutant::Activator
    ]
  end

  # Fences the JSON payload so any loader chatter on stdout can be stripped.
  def loader_script
    lib = File.expand_path("../../lib", __dir__)
    <<~RUBY
      $LOAD_PATH.unshift #{lib.inspect}
      require "henitai/eager_load"
      require "json"
      loaded = ->(name) { $LOADED_FEATURES.any? { |path| path.end_with?(name) } }
      puts "<<<JSON" + JSON.generate(
        defined_constants: #{sample_constants.inspect}.select { |name| Object.const_defined?(name) },
        side_effect_files: SIDE_EFFECT_FILES,
        side_effect_loaded: SIDE_EFFECT_FILES.select(&loaded)
      ) + "JSON>>>"
    RUBY
  end

  # Runs the loader in a clean subprocess and returns the parsed JSON payload.
  # The exit status is asserted (with stderr surfaced) before parsing so an
  # eager-load failure produces an actionable message instead of an opaque
  # JSON parse error. stderr is intentionally not asserted empty: harmless
  # interpreter warnings (e.g. parser version notices) can land there.
  def run_loader
    Dir.mktmpdir do |dir|
      stdout, stderr, status = Open3.capture3("ruby", "-e", loader_script, chdir: dir)
      expect(status).to be_success, "eager load subprocess failed (#{status}):\n#{stderr}"

      payload = stdout[/<<<JSON(.*)JSON>>>/m, 1]
      expect(payload).not_to be_nil,
                             "no JSON payload in subprocess output:\nSTDOUT:\n#{stdout}\nSTDERR:\n#{stderr}"
      JSON.parse(payload)
    end
  end

  it "forces every sampled Henitai constant to load" do
    expect(run_loader.fetch("defined_constants")).to match_array(sample_constants)
  end

  it "does not require the side-effect files" do
    expect(run_loader.fetch("side_effect_loaded")).to be_empty
  end

  it "tracks the coverage and test-hook files as side effects to exclude" do
    expect(run_loader.fetch("side_effect_files")).to contain_exactly(
      "minitest_simplecov.rb",
      "minitest_coverage_hook.rb",
      "rspec_coverage_formatter.rb"
    )
  end
end
# rubocop:enable RSpec/DescribeClass
