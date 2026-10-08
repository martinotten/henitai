# frozen_string_literal: true

require "bundler"
require "json"
require "open3"
require "yaml"

# Runs the oracle corpus (spec/fixtures/oracle) in its weak and strong modes
# and checks the verdicts against what the corpus construction guarantees.
module MutationOracle
  ROOT = File.expand_path(File.join(__dir__, "..", "spec", "fixtures", "oracle"))
  HARNESS_STATUSES = %w[CompileError RuntimeError].freeze

  # One henitai run of the corpus under one configuration.
  class Mode
    attr_reader :name

    def initialize(name, root: ROOT)
      @name = name
      @root = root
    end

    def run!
      Bundler.with_unbundled_env do
        bundle_succeeds?("check") || bundle_succeeds?("install") || raise("bundle install failed in #{@root}")
        _stdout, stderr, = Open3.capture3("bundle", "exec", "henitai", "run", "--config", ".henitai.#{name}.yml",
                                          chdir: @root)
        raise "henitai produced no report for oracle:#{name}\n#{stderr}" unless File.exist?(report_path)
      end
      self
    end

    def mutants
      @mutants ||= JSON.parse(File.read(report_path, encoding: Encoding::UTF_8))
                       .fetch("files").flat_map do |path, file|
        file.fetch("mutants").map { |mutant| mutant.merge("file" => path) }
      end
    end

    def with_status(*statuses)
      mutants.select { |mutant| statuses.include?(mutant.fetch("status")) }
    end

    def harness_reasons
      with_status(*HARNESS_STATUSES).map { |mutant| reason_class(mutant.fetch("statusReason", "")) }.tally
    end

    def key(mutant)
      line = mutant.dig("location", "start", "line")
      "#{relative(mutant.fetch('file'))}:#{line} #{mutant['description'] || mutant['mutatorName']} " \
        "=> #{mutant.fetch('replacement', '').to_s.lines.first.to_s.strip}"
    end

    private

    def bundle_succeeds?(command)
      Open3.capture3("bundle", command, chdir: @root).last.success?
    end

    def report_path
      File.join(@root, "reports", name, "mutation-report.json")
    end

    def relative(path)
      path.delete_prefix("#{@root}/")
    end

    def reason_class(reason)
      reason.sub(/ at line \d+/, "").sub(/(not valid Ruby|activation failed): .*/, '\1: …')
    end
  end

  # Evaluates both modes and prints the oracle summary.
  class Check
    def initialize(weak:, strong:, expected:)
      @weak = weak
      @strong = strong
      @expected = expected
    end

    def violations
      false_kills.map { |mutant| "false kill: #{@weak.key(mutant)}" } +
        false_survivors.map { |mutant| "false survivor: #{@strong.key(mutant)}" }
    end

    def summary
      [mode_line(@weak, "false kills", false_kills.size),
       mode_line(@strong, "false survivors", false_survivors.size),
       *harness_lines].join("\n")
    end

    private

    def false_kills = @weak.with_status("Killed", "Timeout")

    def false_survivors
      allowed = @expected.fetch("allowed_survivors", {}).keys
      @strong.with_status("Survived").reject { |mutant| allowed.include?(@strong.key(mutant)) }
    end

    def mode_line(mode, label, count)
      total = mode.mutants.size
      harness = mode.with_status(*HARNESS_STATUSES).size
      format("oracle:%<name>s mutants=%<total>d %<label>s=%<count>d " \
             "harness_errors=%<harness>d (%<rate>.1f%%) %<tally>s",
             name: mode.name, total:, label:, count:, harness:, rate: rate(harness, total),
             tally: mode.mutants.map { |mutant| mutant.fetch("status") }.tally)
    end

    def harness_lines
      @strong.harness_reasons.sort_by { |_, count| -count }.map do |reason, count|
        format("  %<count>4d  %<reason>s", count:, reason:)
      end
    end

    def rate(part, total) = total.zero? ? 0.0 : 100.0 * part / total
  end
end

desc "Run the oracle corpus and fail on false kills or false survivors"
task :oracle do
  weak = MutationOracle::Mode.new("weak").run!
  strong = MutationOracle::Mode.new("strong").run!
  expected = YAML.safe_load_file(File.join(MutationOracle::ROOT, "expected.yml"))
  check = MutationOracle::Check.new(weak:, strong:, expected:)
  puts check.summary
  violations = check.violations
  abort(["oracle failed:", *violations].join("\n  ")) unless violations.empty?
end
