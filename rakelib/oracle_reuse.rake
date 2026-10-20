# frozen_string_literal: true

require "bundler"
require "fileutils"
require "json"
require "open3"
require "tmpdir"
require "yaml"

# Property check for verdict reuse (WS5): on a scratch copy of the oracle
# corpus, a scripted sequence of edits is applied. After every edit an
# `--incremental` run of the evolving project must produce exactly the
# verdicts of a fresh, history-free full run of the same tree.
module OracleReuse
  ROOT = File.expand_path(File.join(__dir__, "..", "spec", "fixtures", "oracle"))
  HENITAI_ROOT = File.expand_path(File.join(__dir__, ".."))
  CONFIG = ".henitai.strong.yml"
  REPORT = File.join("reports", "strong", "mutation-report.json")
  COPY_EXCLUDES = %w[reports coverage .bundle].freeze

  # Swaps the strong expectations for no-ops once installed: tests keep
  # executing (coverage is unchanged) but stop asserting anything.
  LENIENT_HELPER = <<~RUBY
    # frozen_string_literal: true

    require "rspec/expectations"

    module RSpec
      module Expectations
        def self.fail_with(*) = nil
      end
    end
  RUBY

  # One scratch project directory.
  class Project
    attr_reader :dir

    def initialize(dir)
      @dir = dir
    end

    def path(relative) = File.join(dir, relative)
    def read(relative) = File.read(path(relative))

    def write(relative, content)
      FileUtils.mkdir_p(File.dirname(path(relative)))
      File.write(path(relative), content)
    end

    def copy_to(target)
      FileUtils.mkdir_p(target)
      Dir.children(dir).reject { |name| COPY_EXCLUDES.include?(name) }.each do |name|
        FileUtils.cp_r(path(name), target)
      end
      Project.new(target)
    end

    def run_henitai(*)
      Bundler.with_unbundled_env do
        _out, err, status = Open3.capture3("bundle", "exec", "henitai", "run", "--config", CONFIG, *, chdir: dir)
        raise "henitai failed in #{dir} (#{status.exitstatus})\n#{err}" unless File.exist?(path(REPORT))
      end
      verdicts
    end

    def verdicts
      JSON.parse(read(REPORT)).fetch("files").values.flat_map { |file| file.fetch("mutants") }
    end
  end

  # Builds the starting tree: the strong pricing spec is held back and a
  # covering-but-not-asserting copy of the weak one stands in, so pricing
  # mutants start out Survived and the "add a test" step can flip them.
  class Setup
    def initialize(dir)
      @project = Project.new(ROOT).copy_to(dir)
    end

    def call
      relocate_henitai
      hold_back_strong_pricing_spec
      @project.write("spec/support/strictness.rb", "# frozen_string_literal: true\n")
      @project.write("spec/spec_helper.rb",
                     "#{@project.read('spec/spec_helper.rb')}\nrequire_relative \"support/strictness\"\n")
      @project
    end

    private

    def relocate_henitai
      %w[Gemfile Gemfile.lock].each do |name|
        @project.write(name, @project.read(name).gsub("../../..", HENITAI_ROOT))
      end
    end

    def hold_back_strong_pricing_spec
      strong = "spec/strong/oracle/pricing_spec.rb"
      @project.write("held_back/pricing_spec.rb", @project.read(strong))
      FileUtils.rm(@project.path(strong))
      @project.write("spec/strong/oracle/pricing_smoke_spec.rb", @project.read("spec/weak/oracle/pricing_spec.rb"))
    end
  end

  # The scripted edit sequence. Each edit keeps the baseline suite green.
  EDITS = {
    "baseline" => ->(_project) {},
    "edit source" => lambda do |project|
      cart = "lib/oracle/cart.rb"
      project.write(cart, project.read(cart).sub("count + 1", "# one more item\n      count + 1"))
    end,
    "add a test" => lambda do |project|
      project.write("spec/strong/oracle/pricing_spec.rb", project.read("held_back/pricing_spec.rb"))
    end,
    "edit a helper" => ->(project) { project.write("spec/support/strictness.rb", LENIENT_HELPER) },
    "change config" => lambda do |project|
      config = YAML.safe_load_file(project.path(CONFIG))
      config["test_excludes"] += ["spec/strong/oracle/cart_spec.rb"]
      project.write(CONFIG, YAML.dump(config))
    end
  }.freeze

  # Runs the sequence and collects one line per step plus any mismatch.
  class Check
    def initialize(workdir)
      @workdir = workdir
      @project = Setup.new(File.join(workdir, "incremental")).call
    end

    def call
      EDITS.each_with_index.map do |(name, edit), index|
        edit.call(@project)
        compare(name, @project.run_henitai("--incremental"), fresh_verdicts(index))
      end
    end

    private

    def fresh_verdicts(index)
      @project.copy_to(File.join(@workdir, "fresh-#{index}")).run_henitai
    end

    def compare(step, incremental, fresh)
      actual = statuses(incremental)
      expected = statuses(fresh)
      { step:, mutants: expected.size, reused: incremental.count { |m| m["fromCache"] },
        tally: expected.values.tally, mismatches: mismatches(actual, expected) }
    end

    def mismatches(actual, expected)
      (actual.keys | expected.keys).reject { |id| actual[id] == expected[id] }
                                   .map { |id| "#{id}: #{actual[id]} != #{expected[id]}" }
    end

    def statuses(mutants) = mutants.to_h { |mutant| [mutant.fetch("stableId"), mutant.fetch("status")] }
  end
end

namespace :oracle do
  desc "Check that --incremental verdicts equal a fresh full run across scripted edits"
  task :reuse do
    results = Dir.mktmpdir("henitai-oracle-reuse") { |dir| OracleReuse::Check.new(dir).call }
    results.each do |result|
      puts format("oracle:reuse %<step>-14s mutants=%<mutants>d reused=%<reused>d mismatches=%<count>d %<tally>s",
                  **result, count: result[:mismatches].size)
    end
    failures = results.flat_map { |result| result[:mismatches].map { |line| "#{result[:step]}: #{line}" } }
    abort(["oracle:reuse failed:", *failures].join("\n  ")) unless failures.empty?
    abort("oracle:reuse is vacuous: no verdict was reused") if results.sum { |result| result[:reused] }.zero?
  end
end
