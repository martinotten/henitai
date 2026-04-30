# frozen_string_literal: true

module Henitai
  # Wakeup pipe used to interrupt child-process wait loops when CHLD arrives.
  class ProcessWakeup
    def initialize(signal_name: "CHLD")
      @signal_name = signal_name
      @reader, @writer = IO.pipe
    end

    def install
      @previous_handler = Signal.trap(signal_name) { signal }
      self
    end

    def wait(timeout)
      # rubocop:disable Lint/IncompatibleIoSelectWithFiberScheduler
      IO.select([reader], nil, nil, timeout)
      # rubocop:enable Lint/IncompatibleIoSelectWithFiberScheduler
    rescue Errno::EINTR
      nil
    end

    def drain
      loop do
        reader.read_nonblock(4096)
      end
    rescue IO::WaitReadable, EOFError
      nil
    end

    def signal
      writer.write_nonblock(".")
    rescue IO::WaitWritable, IOError, Errno::EPIPE
      nil
    end

    def close
      Signal.trap(signal_name, previous_handler) if previous_handler
    ensure
      reader.close unless reader.closed?
      writer.close unless writer.closed?
    end

    private

    attr_reader :previous_handler, :reader, :signal_name, :writer
  end
end
