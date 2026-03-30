# frozen_string_literal: true

module Henitai
  # Orchestrates the full mutation testing pipeline.
  #
  # Pipeline phases (Phase-Gate model):
  #
  #   Gate 1 — Subject selection
  #     Resolve source files from includes, apply --since filter (incremental),
  #     build Subject list from AST.
  #
  #   Gate 2 — Mutant generation
  #     Apply operators to each Subject's AST. Filter arid (non-productive)
  #     nodes via ignore_patterns. Produces the initial mutant list.
  #
  #   Gate 3 — Static filtering
  #     Remove ignored mutants (pattern matches), compile-time errors.
  #     Apply per-test coverage data: mark :no_coverage for uncovered mutants.
  #
  #   Gate 4 — Mutant execution
  #     Run surviving mutants in isolated child processes (fork isolation).
  #     Each child process loads the test suite with the mutated method
  #     injected via Module#define_method. Collect kill/survive/timeout results.
  #
  #   Gate 5 — Reporting
  #     Write results to configured reporters (terminal, html, json, dashboard).
  #
  class Runner
    attr_reader :config, :result

    def initialize(config: Configuration.load, subjects: nil, since: nil)
      @config   = config
      @subjects = subjects
      @since    = since
    end

    # Entry point — runs the full pipeline and returns a Result.
    # @return [Result]
    def run
      # TODO: implement pipeline phases
      raise NotImplementedError, "Runner#run is not yet implemented"
    end

    private

    def resolve_subjects
      # Gate 1: discover source files, parse ASTs, build Subject objects
      raise NotImplementedError
    end

    def generate_mutants(subjects)
      # Gate 2: apply operators, filter arid nodes
      raise NotImplementedError
    end

    def filter_mutants(mutants)
      # Gate 3: static filtering, coverage data
      raise NotImplementedError
    end

    def execute_mutants(mutants)
      # Gate 4: fork-based isolation, collect results
      raise NotImplementedError
    end

    def report(result)
      # Gate 5: invoke each configured reporter
      raise NotImplementedError
    end
  end
end
