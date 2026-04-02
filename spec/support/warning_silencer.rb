# frozen_string_literal: true

module SpecSupport
  module WarningSilencer
    SILENCED_PATTERNS = [
      /parser\/current is loading parser\/ruby33/,
      /method redefined; discarding old value/,
      /previous definition of value was here/,
      /character class has duplicated range:/,
      /string returned by :foo\.to_s will be frozen in the future/
    ].freeze

    def self.install!
      return if @installed

      @installed = true
      Warning.singleton_class.prepend(WarningPatch)
      Kernel.prepend(KernelPatch)
    end

    def self.silence?(message)
      text = message.to_s
      SILENCED_PATTERNS.any? { |pattern| pattern.match?(text) }
    end

    module WarningPatch
      def warn(message = nil, *arguments, **keywords)
        return if SpecSupport::WarningSilencer.silence?(message)

        super
      end
    end

    module KernelPatch
      def warn(message = nil, *arguments, **keywords)
        return if SpecSupport::WarningSilencer.silence?(message)

        super
      end
    end
  end
end

SpecSupport::WarningSilencer.install!
