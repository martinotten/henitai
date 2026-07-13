# frozen_string_literal: true

module Henitai
  class CLI
    # Option definitions specific to `henitai run`, mixed into {Options} to
    # keep each module focused: {Options} owns parser construction and the
    # shared options, this module owns the run-only flags.
    module RunOptions
      private

      def add_since_option(opts, options)
        opts.on("--since GIT_REF", "Only mutate subjects changed since GIT_REF") do |ref|
          options[:since] = ref
        end
      end

      def add_integration_option(opts, options)
        opts.on("--use INTEGRATION", "Test framework integration (rspec)") do |name|
          options[:integration] = name
        end
      end

      def add_operator_option(opts, options)
        opts.on("--operators SET", "Operator set: light | full") do |set|
          options[:operators] = set
        end
      end

      def add_timeout_multiplier_option(opts, options)
        opts.on(
          "--timeout-multiplier N", Float,
          "Multiplier applied to the measured per-mutant test baseline " \
          "when mutation.timeout is unset (default: 3.0)"
        ) do |n|
          options[:timeout_multiplier] = n
        end
      end

      def add_jobs_option(opts, options)
        opts.on("--jobs N", Integer, "Number of parallel workers (default: 1)") do |n|
          options[:jobs] = n
        end
      end

      def add_output_option(opts, options)
        opts.on("--all-logs", "--verbose", "Print all captured child logs") do
          options[:all_logs] = true
        end
      end

      def add_survivors_from_option(opts, options)
        opts.on(
          "--survivors-from PATH",
          "Re-run only survivors from a prior report " \
          "(partial rerun; threshold checks are skipped; dirty worktrees are included)"
        ) do |path|
          options[:survivors_from] = path
        end
      end

      def add_dry_run_option(opts, options)
        opts.on(
          "--dry-run",
          "List the post-filter mutant set without executing mutants (always exits 0)"
        ) do
          options[:dry_run] = true
        end
      end

      def add_incremental_option(opts, options)
        opts.on(
          "--incremental",
          "Reuse still-valid Killed verdicts from the history store instead of re-executing them"
        ) do
          options[:incremental] = true
        end
      end

      def add_force_option(opts, options)
        opts.on(
          "--force",
          "Bypass verdict reuse and execute every mutant (only meaningful with --incremental)"
        ) do
          options[:force] = true
        end
      end

      def add_fail_on_survivors_option(opts, options)
        opts.on(
          "--fail-on-survivors",
          "Exit 1 for partial reruns when any survivors remain (otherwise exits 0)"
        ) do
          options[:fail_on_survivors] = true
        end
      end

      def add_strict_exit_codes_option(opts, options)
        opts.on(
          "--strict-exit-codes",
          "Expanded exit codes: 0 threshold met, 1 threshold miss, " \
          "2 framework error, 3 timeouts present, 4 runtime/compile errors present"
        ) do
          options[:strict_exit_codes] = true
        end
      end
    end
  end
end
