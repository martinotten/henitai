# frozen_string_literal: true

require "json"

module Henitai
  class CLI
    # Implements `henitai run`: option parsing, pipeline execution, survivors
    # resolution, and exit-status derivation. Mixed into {CLI} so it shares the
    # instance (and observable +exit+/+warn+ calls).
    module RunCommand
      private

      def run_command
        @command_halted = false
        options = parse_run_options
        return if @command_halted

        config = load_config(options)
        result = run_pipeline(options, config)
        exit(run_exit_status(result, config, options))
      rescue StandardError => e
        handle_run_error(e)
      end

      def run_exit_status(result, config, options)
        # A dry run tests nothing, so there is no score to gate on.
        return 0 if options[:dry_run]

        exit_status_for(
          result,
          config,
          fail_on_survivors: options[:fail_on_survivors],
          strict_exit_codes: options[:strict_exit_codes]
        )
      end

      def run_pipeline(options, config)
        resolved_survivors_from = resolve_survivors_from(options[:survivors_from])
        runner = Runner.new(
          config:,
          subjects: subjects_from_argv,
          since: options[:since],
          survivors_from: resolved_survivors_from,
          mode: {
            dry_run: options.fetch(:dry_run, false),
            incremental: options.fetch(:incremental, false) && !options.fetch(:force, false)
          }
        )
        runner.run
      end

      def subjects_from_argv
        @argv.empty? ? nil : @argv.map { |expr| Subject.parse(expr) }
      end

      def resolve_survivors_from(survivors_from)
        return nil if survivors_from.nil?

        # Fast path: if the path already points into reports/sessions/<session_id>/,
        # keep it as-is so activation-recipes.json can be found by the runner.
        report_dir = File.dirname(survivors_from)
        parent_dir = File.dirname(report_dir)
        # Heuristic: treat any path under a directory named "sessions" as already
        # being a snapshot path; this keeps activation-recipes lookup correct.
        return survivors_from if File.basename(parent_dir) == "sessions"

        session_id = session_id_from_report(survivors_from)
        return survivors_from if session_id.nil?

        snapshot_path = survivors_snapshot_path(report_dir, session_id)
        recipe_path = File.join(report_dir, "sessions", session_id, "activation-recipes.json")
        return snapshot_path if File.exist?(recipe_path) && File.exist?(snapshot_path)

        # If the recipes exist but the snapshot doesn't (e.g. partial cleanup),
        # fall back to the path the user provided so the error message points
        # at what they actually passed.

        survivors_from
      rescue StandardError => e
        warn_survivors_from_resolution_error(survivors_from, e)
        survivors_from
      end

      def survivors_snapshot_path(report_dir, session_id)
        File.join(report_dir, "sessions", session_id, "mutation-report.json")
      end

      def session_id_from_report(path)
        parsed = JSON.parse(File.read(path))
        parsed["sessionId"]
      rescue JSON::ParserError, Errno::ENOENT
        nil
      end

      def exit_status_for(result, config, fail_on_survivors: false, strict_exit_codes: false)
        if result.respond_to?(:partial_rerun?) && result.partial_rerun?
          warn "henitai: partial rerun - mutation score threshold not evaluated"
          return result.survived.positive? ? 1 : 0 if fail_on_survivors

          return 0
        end

        strict_status = strict_exit_codes ? strict_status_for(result) : nil
        strict_status || threshold_status_for(result, config)
      end

      # Expanded, opt-in exit codes (precedence: timeout > runtime/compile
      # error > threshold miss). The timeout code is informational and
      # independent of coverage_criteria.timeout: a run can pass its threshold
      # and still exit 3.
      def strict_status_for(result)
        statuses = result.mutants.map(&:status)
        return 3 if statuses.include?(:timeout)
        return 4 if statuses.include?(:runtime_error) || statuses.include?(:compile_error)

        nil
      end

      def threshold_status_for(result, config)
        score = result.mutation_score
        # No valid mutants to evaluate (e.g. an incremental run with no changed
        # code) cannot fail a threshold — treat it as success.
        return 0 if score.nil?

        score.to_i >= config.thresholds.fetch(:low, 60) ? 0 : 1
      end

      def warn_survivors_from_resolution_error(survivors_from, error)
        warn(
          "henitai: warning: could not resolve survivors-from " \
          "#{survivors_from}: #{error.class}: #{error.message}"
        )
      end
    end
  end
end
