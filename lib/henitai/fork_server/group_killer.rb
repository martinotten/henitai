# frozen_string_literal: true

module Henitai
  module ForkServer
    # Signals a mutant process the fork server forked. Such a process leads
    # its own process group only once its bootstrap ran +setpgid+, so until
    # then the group does not exist and the process itself is signalled.
    # Its parent is the server, so it is never ours to wait on.
    module GroupKiller
      # @param leader [Boolean] whether the pid itself may still be alive;
      #   false once it was reaped, when only stragglers in its group remain
      def self.kill(pid, signal = :SIGKILL, leader: true)
        Process.kill(signal, -pid)
      rescue Errno::ESRCH
        kill_leader(pid, signal) if leader
      rescue Errno::EPERM
        nil
      end

      def self.kill_leader(pid, signal)
        Process.kill(signal, pid)
      rescue Errno::ESRCH, Errno::EPERM
        nil
      end
      private_class_method :kill_leader

      # Signal 0 probes existence only; a missing process or group is not alive.
      def self.alive?(pid, leader: true)
        Process.kill(0, -pid)
        true
      rescue Errno::ESRCH
        leader && probe(pid)
      rescue Errno::EPERM
        true
      end

      def self.probe(pid)
        Process.kill(0, pid)
        true
      rescue Errno::ESRCH
        false
      rescue Errno::EPERM
        true
      end
      private_class_method :probe
    end
  end
end
