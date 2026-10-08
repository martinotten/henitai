# frozen_string_literal: true

module Oracle
  # Its superclass lives in another file (EXE-01): activating a mutant here
  # must not load this file on its own and fail on the missing constant.
  class Cart < Base
    def items(count)
      count + 1
    end
  end
end
