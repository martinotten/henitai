# frozen_string_literal: true

require "socket"
require "fileutils"

module Henitai
  module ForkServer
    # Forks the fork server from the parent, after the mutants exist, and
    # returns the parent's Client for it. In the server process: set up like
    # any mutant child, send boot output to a log file, boot the integration
    # environment once, then serve requests until told to stop.
    class ServerProcess
      def self.start(integration:, mutants:, test_files:, log_path:)
        new(integration:, mutants:, test_files:, log_path:).start
      end

      def initialize(integration:, mutants:, test_files:, log_path:)
        @integration = integration
        @mutants = mutants.to_h { |mutant| [mutant.id, mutant] }
        @test_files = test_files
        @log_path = log_path
      end

      # @return [Client]
      def start
        FileUtils.mkdir_p(File.dirname(@log_path))
        parent_socket, server_socket = UNIXSocket.pair
        parent_pid = Process.pid
        pid = Process.fork do
          parent_socket.close
          serve(server_socket, parent_pid)
        end
        server_socket.close
        Client.new(socket: parent_socket, pid:)
      end

      private

      def serve(socket, parent_pid)
        Integration::ChildBootstrap.after_fork!(parent_pid:)
        redirect_output
        wake_reader, wake_writer = IO.pipe
        launcher = Launcher.new(integration: @integration, mutants: @mutants, socket:)
        boot = -> { boot_environment(wake_writer) }
        Server.new(socket:, boot:, launcher:, wake_reader:).serve
        Process.exit!(0)
      end

      def boot_environment(wake_writer)
        @integration.preload_environment(@test_files)
        Signal.trap("CHLD") { wake(wake_writer) }
      end

      def wake(writer)
        writer.write_nonblock(".")
      rescue IO::WaitWritable, IOError
        nil
      end

      def redirect_output
        File.open(@log_path, "w") do |log|
          $stdout.reopen(log)
          $stderr.reopen(log)
        end
        $stdin.reopen(File::NULL)
        $stdout.sync = true
        $stderr.sync = true
      end
    end
  end
end
