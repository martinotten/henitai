# frozen_string_literal: true

require "bundler"
require "fileutils"
require "json"
require "open3"
require "tmpdir"
require "yaml"

# End-to-end check for resumable runs (ADR-19, plan step 8): a run of the
# oracle corpus is interrupted by a real signal once it has checkpointed
# some verdicts, then resumed with `--incremental`. The interrupted run must
# leave a consistent history without a trend row, no process behind and a
# resume hint; the resumed run must reuse verdicts and produce exactly the
# verdicts of a fresh, history-free run of the same tree.
#
# Every signal runs against every execution setting. Since ADR-20 there is
# one driver, so the settings differ only in slot count and fork server.
module OracleResume
  SIGNALS = %w[INT TERM HUP].freeze
  SETTINGS = {
    "jobs 1" => {},
    "jobs 2" => { "jobs" => 2 },
    "jobs 1 fork server" => { "mutation" => { "fork_server" => true } },
    "jobs 2 fork server" => { "jobs" => 2, "mutation" => { "fork_server" => true } }
  }.freeze
  HISTORY = File.join("reports", "strong", "mutation-history.sqlite3")
  COMMITTED_BEFORE_SIGNAL = 10
  CHECKPOINTS = { "reports" => { "checkpoint_every" => 5 } }.freeze
  RUN_TIMEOUT = 300
  PROCESS_GRACE = 10
  PACE_ENV = "ORACLE_RESUME_PACE"
  # Slows every test process down while PACE_ENV is set, so a run is still
  # going when the signal arrives. The file is identical in every copy and
  # unset for the resume and the fresh runs, so it changes no fingerprint.
  PACE_HELPER = <<~RUBY.freeze
    # frozen_string_literal: true

    RSpec.configure do |config|
      config.before(:suite) { sleep(Float(ENV.fetch("#{PACE_ENV}", "0"))) }
    end
  RUBY
  PACE_SECONDS = "0.4"

  # One project copy, run until COMMITTED_BEFORE_SIGNAL verdicts are in the
  # history, then signalled.
  class InterruptedRun
    def initialize(project, signal)
      @project = project
      @signal = signal
    end

    # @return [Hash] exit status, stderr, committed verdicts, trend rows,
    #   integrity check result and leftover processes
    def call
      err_path = @project.path("interrupted.stderr")
      pid = spawn_henitai(err_path)
      committed = wait_for_checkpoints(pid)
      Process.kill(@signal, pid)
      _, status = Process.wait2(pid)
      { status:, stderr: File.read(err_path), committed:, leftovers: leftover_processes, **history_state }
    end

    private

    def spawn_henitai(err_path)
      Bundler.with_unbundled_env do
        Process.spawn({ PACE_ENV => PACE_SECONDS }, "bundle", "exec", "henitai", "run", "--config", OracleReuse::CONFIG,
                      chdir: @project.dir, out: File::NULL, err: err_path)
      end
    end

    def wait_for_checkpoints(pid)
      deadline = monotonic + RUN_TIMEOUT
      loop do
        count = committed_verdicts
        return count if count >= COMMITTED_BEFORE_SIGNAL
        if Process.wait(pid, Process::WNOHANG)
          raise "run ended before #{COMMITTED_BEFORE_SIGNAL} verdicts were checkpointed"
        end
        raise "no checkpoint within #{RUN_TIMEOUT}s" if monotonic > deadline

        sleep 0.2
      end
    end

    def committed_verdicts
      query("SELECT COUNT(*) FROM mutants").to_i
    rescue StandardError
      0
    end

    def history_state
      { runs: query("SELECT COUNT(*) FROM runs").to_i, integrity: query("PRAGMA integrity_check") }
    end

    def query(sql)
      path = @project.path(HISTORY)
      return nil unless File.exist?(path)

      require "sqlite3"
      db = SQLite3::Database.new(path, readonly: true)
      db.busy_timeout = 2000
      db.get_first_value(sql)
    ensure
      db&.close
    end

    # Mutant children lead their own process groups and fork-server
    # grandchildren are not our children, so leftovers are found by command
    # line. Orphans exit through their watchdog; give them its poll window.
    def leftover_processes
      deadline = monotonic + PROCESS_GRACE
      loop do
        found = henitai_processes
        return found if found.empty? || monotonic > deadline

        sleep 0.5
      end
    end

    def henitai_processes
      out, = Open3.capture2("ps", "-A", "-o", "pid=,command=")
      out.lines.grep(/henitai run --config #{Regexp.escape(OracleReuse::CONFIG)}/).map(&:strip)
    end

    def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  # Runs one scenario: set up, interrupt, optionally edit, resume, compare.
  class Scenario
    attr_reader :name

    def initialize(name, workdir, signal:, setting:, after_interrupt: nil)
      @name = name
      @workdir = workdir
      @signal = signal
      @setting = setting
      @after_interrupt = after_interrupt
    end

    def call(fresh)
      project = configured_project
      interrupted = InterruptedRun.new(project, @signal).call
      @after_interrupt&.call(project)
      resumed = project.run_henitai("--incremental")
      result(interrupted, resumed, fresh.call(project))
    end

    private

    def configured_project
      project = OracleReuse::Setup.new(File.join(@workdir, name.tr(" ", "-"))).call
      config = YAML.safe_load_file(project.path(OracleReuse::CONFIG))
      project.write(OracleReuse::CONFIG, YAML.dump(deep_merge(config, @setting.merge(CHECKPOINTS))))
      project.write("spec/support/pace.rb", PACE_HELPER)
      project.write("spec/spec_helper.rb", "#{project.read('spec/spec_helper.rb')}require_relative \"support/pace\"\n")
      project
    end

    def deep_merge(base, extra)
      base.merge(extra) { |_key, left, right| left.is_a?(Hash) ? deep_merge(left, right) : right }
    end

    def result(interrupted, resumed, expected)
      { name:, committed: interrupted[:committed], reused: resumed.count { |m| m["fromCache"] },
        problems: interrupt_problems(interrupted) + reuse_problems(resumed, expected) }
    end

    def interrupt_problems(run)
      [
        ("exited successfully" if run[:status].success?),
        ("no resume hint on stderr" unless run[:stderr].include?("resume with --incremental")),
        ("trend rows after the abort: #{run[:runs]}" unless run[:runs].zero?),
        ("history integrity: #{run[:integrity]}" unless run[:integrity] == "ok"),
        *run[:leftovers].map { |process| "process left behind: #{process}" }
      ].compact
    end

    def reuse_problems(resumed, expected)
      actual = statuses(resumed)
      mismatches = (actual.keys | expected.keys).reject { |id| actual[id] == expected[id] }
                                                .map { |id| "#{id}: #{actual[id]} != #{expected[id]}" }
      mismatches << "nothing reused" if resumed.none? { |m| m["fromCache"] }
      mismatches
    end

    def statuses(mutants) = mutants.to_h { |mutant| [mutant.fetch("stableId"), mutant.fetch("status")] }
  end

  # The all-cached resume: a run that completed, then `--incremental`.
  class CompletedScenario < Scenario
    def call(fresh)
      project = configured_project
      completed = project.run_henitai.size
      resumed = project.run_henitai("--incremental")
      { name:, committed: completed, reused: resumed.count { |m| m["fromCache"] },
        problems: reuse_problems(resumed, fresh.call(project)) }
    end
  end

  # Fresh verdicts per tree: a history-free copy of the scenario's project,
  # cached by the tree's test files (edits change them).
  class FreshRuns
    def initialize(workdir)
      @workdir = workdir
      @cache = {}
    end

    def call(project)
      @cache[tree_key(project)] ||= run_fresh(project)
    end

    private

    def tree_key(project)
      Dir.glob(project.path("spec/**/*.rb")).map { |path| [path.delete_prefix(project.dir), File.read(path)] }
    end

    def run_fresh(project)
      copy = project.copy_to(File.join(@workdir, "fresh-#{@cache.size}"))
      FileUtils.rm_f(copy.path(HISTORY))
      copy.run_henitai.to_h { |mutant| [mutant.fetch("stableId"), mutant.fetch("status")] }
    end
  end

  def self.scenarios(workdir)
    matrix = SETTINGS.flat_map do |label, setting|
      SIGNALS.map { |signal| Scenario.new("#{signal} #{label}", workdir, signal:, setting:) }
    end
    matrix << Scenario.new("INT then test edit", workdir, signal: "INT", setting: {},
                                                          after_interrupt: OracleReuse::EDITS.fetch("add a test"))
    matrix << CompletedScenario.new("completed then resumed", workdir, signal: nil, setting: {})
  end
end

namespace :oracle do
  desc "Interrupt oracle runs with INT/TERM/HUP and check that --incremental resumes them exactly"
  task :resume do
    results = Dir.mktmpdir("henitai-oracle-resume") do |dir|
      fresh = OracleResume::FreshRuns.new(dir)
      OracleResume.scenarios(dir).map { |scenario| scenario.call(fresh) }
    end
    results.each do |result|
      puts format("oracle:resume %<name>-24s committed=%<committed>d reused=%<reused>d problems=%<count>d",
                  **result, count: result[:problems].size)
    end
    failures = results.flat_map { |result| result[:problems].map { |line| "#{result[:name]}: #{line}" } }
    abort(["oracle:resume failed:", *failures].join("\n  ")) unless failures.empty?
  end
end
