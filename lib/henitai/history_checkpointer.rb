# frozen_string_literal: true

module Henitai
  # Progress observer that checkpoints verdicts into the history store while
  # a run is in progress, so an aborted run can be resumed with
  # `--incremental` (ADR-19). Every verdict it sees is final: a
  # {ControlGate} sits in front of all progress observers.
  #
  # Batches with the cadence of {CheckpointReporter} (`checkpoint_every`,
  # `checkpoint_interval`). A failed write is contained like the end-of-run
  # write: one warning, no further checkpoints, the run goes on, and the
  # end-of-run `record` still writes every verdict.
  class HistoryCheckpointer
    # @return [Integer] verdicts in committed checkpoint transactions
    attr_reader :committed

    # rubocop:disable Metrics/ParameterLists -- one keyword per collaborator
    def initialize(history_store:, config:, run_id:, version: Henitai::VERSION,
                   clock: CheckpointReporter::MONOTONIC, warner: ->(message) { Kernel.warn(message) })
      # rubocop:enable Metrics/ParameterLists
      @history_store = history_store
      @config = config
      @run_id = run_id
      @version = version
      @clock = clock
      @warner = warner
      @batch = []
      @committed = 0
      @last_flush_at = clock.call
    end

    def progress(mutant, **)
      return if @disabled

      @batch << mutant
      flush if due?
    end

    # Writes the pending verdicts. The count is updated inside the same
    # signal-deferral section as the write, so a signal arriving during the
    # write cannot leave a committed batch uncounted.
    def flush
      return if @disabled || @batch.empty?

      SignalDeferral.call { commit(@batch) }
    rescue StandardError => e
      disable(e)
    end

    private

    def due?
      @batch.size >= @config.checkpoint_every ||
        (@clock.call - @last_flush_at) >= @config.checkpoint_interval
    end

    def commit(batch)
      @committed += @history_store.checkpoint(
        batch, version: @version, run_id: @run_id, operators: @config.operators
      )
      @batch = []
      @last_flush_at = @clock.call
    end

    def disable(error)
      @disabled = true
      @batch = []
      @warner.call("henitai: could not checkpoint mutation history (#{error.class}: #{error.message}); " \
                   "verdicts are recorded at the end of the run")
    end
  end
end
