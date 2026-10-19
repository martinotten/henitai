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

      # Stands in for a process whose end the lost server never relayed. It
      # says nothing about the mutant, so it must never become a verdict.
      def self.lost
        new(exitstatus: nil, termsig: 9, lost: true)
      end

      def initialize(exitstatus:, termsig:, lost: false)
        @exitstatus = exitstatus
        @termsig = termsig
        @lost = lost
      end

      def lost?
        @lost
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
