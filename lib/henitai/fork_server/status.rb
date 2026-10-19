# frozen_string_literal: true

module Henitai
  module ForkServer
    # Stands in for Process::Status of a mutant process that the parent cannot
    # wait on itself: the fork server reaps it and relays how it ended.
    # Answers the subset MutantVerdict and ScenarioExecutionResult read.
    class Status
      attr_reader :exitstatus, :termsig

      def self.from_event(event)
        new(exitstatus: event["exitstatus"], termsig: event["termsig"])
      end

      def self.from_process_status(status)
        new(exitstatus: status.exitstatus, termsig: status.termsig)
      end

      def initialize(exitstatus:, termsig:)
        @exitstatus = exitstatus
        @termsig = termsig
      end

      def exited?
        !signaled?
      end

      def signaled?
        !termsig.nil?
      end

      def success?
        !signaled? && exitstatus.to_i.zero?
      end

      def to_event
        { "exitstatus" => exitstatus, "termsig" => termsig }
      end
    end
  end
end
