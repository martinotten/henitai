# frozen_string_literal: true

module Henitai
  class ExecutionEngine
    # Run-scoped ENV/working-directory setup for {ExecutionEngine}: exposes the
    # reports dir, mutation-coverage dir, per-stream log cap and worker-slot
    # index to forked children via ENV, restoring the prior values afterwards.
    # Extracted so the engine class stays focused on execution scheduling.
    module EnvScope
      private

      def with_reports_dir(config)
        original = ENV.fetch("HENITAI_REPORTS_DIR", nil)
        ENV["HENITAI_REPORTS_DIR"] = config.reports_dir
        yield
      ensure
        restore_env("HENITAI_REPORTS_DIR", original)
      end

      def with_coverage_dir(config)
        original = ENV.fetch("HENITAI_COVERAGE_DIR", nil)
        ENV["HENITAI_COVERAGE_DIR"] = mutation_coverage_dir(config)
        yield
      ensure
        restore_env("HENITAI_COVERAGE_DIR", original)
      end

      def with_max_log_bytes(config)
        cap = config.respond_to?(:max_log_bytes) ? config.max_log_bytes : nil
        return yield if cap.nil?

        env_key = Integration::ScenarioLogSupport::MAX_LOG_BYTES_ENV
        original = ENV.fetch(env_key, nil)
        ENV[env_key] = cap.to_s
        yield
      ensure
        restore_env(env_key, original) if cap
      end

      # Linear-path children inherit slot 0 so suite-side isolation code works
      # identically in both execution modes; the parallel scheduler overwrites
      # the value per spawn. Restored afterwards like the other run-scoped vars.
      def with_worker_slot
        original = ENV.fetch(SlotScheduler::WORKER_SLOT_ENV, nil)
        ENV[SlotScheduler::WORKER_SLOT_ENV] = "0"
        yield
      ensure
        restore_env(SlotScheduler::WORKER_SLOT_ENV, original)
      end

      def restore_env(key, original)
        if original.nil?
          ENV.delete(key)
        else
          ENV[key] = original
        end
      end

      def mutation_coverage_dir(config)
        base_dir = config.respond_to?(:reports_dir) ? config.reports_dir : nil
        base_dir = "reports" if base_dir.nil? || base_dir.empty?

        File.join(base_dir, "mutation-coverage")
      end
    end
  end
end
