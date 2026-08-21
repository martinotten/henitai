# frozen_string_literal: true

module Henitai
  # Makes a forked mutant child exit when its parent dies.
  #
  # Children `setpgid(0, 0)` into their own process group, and all parent-side
  # cleanup (timeout kills, graceful drain, signal traps) only runs while the
  # parent's event loop is alive. If the parent is SIGKILLed, OOM-killed, or
  # crashes, its children receive no signal at all: they reparent to init and
  # keep running, each holding a full Ruby and test-framework image. Runs have
  # been observed leaving a dozen such orphans behind, several gigabytes in
  # total.
  #
  # A child cannot be told to die by a parent that is already gone, so it has
  # to notice by itself. This is a poll: portable, and cheap enough at a
  # multi-second interval that it costs nothing next to running a test suite.
  # PDEATHSIG (Linux) and kqueue NOTE_EXIT (macOS) would be prompter but are
  # platform-specific; they can be layered on later behind the same interface.
  class OrphanWatchdog
    DEFAULT_INTERVAL = 1.5
    ENV_ENABLED = "HENITAI_CHILD_WATCHDOG"
    ENV_INTERVAL = "HENITAI_CHILD_WATCHDOG_INTERVAL"

    # Exit code used when the watchdog fires. 2 classifies as :compile_error
    # (see ScenarioExecutionResult.status_for), which surfaces in reports and
    # logs. Codes at 3 and above classify as :killed, which would let a
    # false positive silently inflate the mutation score -- so a visibly wrong
    # verdict is preferred to an invisibly wrong one. In the true-positive case
    # the parent is dead and nothing classifies this child at all.
    ORPHAN_EXIT_CODE = 2

    # Captured at load time, for the same reason as ProcessLiveness::KILL: the
    # mutant child runs the host project's own suite, and a spec there stubbing
    # `Process.ppid` would otherwise make this child believe it had been
    # reparented and exit itself.
    PPID = Process.method(:ppid)

    # Opt-OUT, deliberately inverted relative to HENITAI_DEBUG_CHILD's opt-in:
    # a watchdog that defaulted to off would never protect the runs it exists
    # for. Set HENITAI_CHILD_WATCHDOG=0 to disable.
    def self.enabled?(env = ENV)
      env[ENV_ENABLED] != "0"
    end

    def self.poll_interval(env = ENV)
      seconds = Float(env[ENV_INTERVAL], exception: false)
      seconds&.positive? ? seconds : DEFAULT_INTERVAL
    end

    # Starts the watchdog in a background thread. Call in the child, right
    # after fork, with the pid captured in the parent beforehand.
    #
    # @return [Thread, nil] nil when disabled
    def self.start(parent_pid:, env: ENV)
      return nil unless enabled?(env)

      watchdog = new(parent_pid:, interval: poll_interval(env))
      Thread.new { watchdog.run }
    end

    # Every collaborator is injectable so the decision logic can be specced
    # without forking a process or waiting on a real clock.
    # rubocop:disable Metrics/ParameterLists
    def initialize(parent_pid:, interval: DEFAULT_INTERVAL, liveness: ProcessLiveness,
                   ppid: PPID, on_orphan: nil, sleeper: nil)
      @parent_pid = parent_pid
      @interval   = interval
      @liveness   = liveness
      @ppid       = ppid
      @on_orphan  = on_orphan || -> { Kernel.exit!(ORPHAN_EXIT_CODE) }
      @sleeper    = sleeper || ->(seconds) { Kernel.sleep(seconds) }
    end
    # rubocop:enable Metrics/ParameterLists

    # Two arms, because neither alone is sufficient. A changed ppid is
    # definitive -- we have been reparented, and no pid reuse can fake that --
    # but it stays equal while the parent lingers as a zombie, which the
    # liveness probe catches.
    def orphaned?
      @ppid.call != @parent_pid || !@liveness.alive?(@parent_pid)
    end

    # Polls until orphaned, then hands over to the orphan handler -- which by
    # default calls exit! and so never returns. Checks before sleeping, so a
    # child forked from an already-dead parent dies immediately rather than
    # after one interval.
    def run
      @sleeper.call(@interval) until orphaned?

      @on_orphan.call
    end
  end
end
