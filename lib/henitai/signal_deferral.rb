# frozen_string_literal: true

module Henitai
  # Holds INT, TERM and HUP back while a block runs, then re-sends the first
  # one that arrived (ADR-19). A history write therefore commits or rolls
  # back as a whole before the signal takes effect.
  #
  # `Thread.handle_interrupt` cannot do this: it does not defer the
  # `Interrupt` Ruby raises for a signal on the main thread.
  module SignalDeferral
    SIGNALS = %w[INT TERM HUP].freeze
    RESEND = ->(signal) { Process.kill(signal, Process.pid) }

    module_function

    def call(resend: RESEND)
      pending = nil
      saved = SIGNALS.to_h { |signal| [signal, Signal.trap(signal) { pending ||= signal }] }
      yield
    ensure
      saved&.each { |signal, handler| Signal.trap(signal, handler) }
      resend.call(pending) if pending
    end
  end
end
