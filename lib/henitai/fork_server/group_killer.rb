# frozen_string_literal: true

module Henitai
  module ForkServer
    # Kills the process group of a mutant process that is still running.
    module GroupKiller
      def self.kill(pid)
        Process.kill(:SIGKILL, -pid)
      rescue Errno::ESRCH, Errno::EPERM
        nil
      end
    end
  end
end
