# frozen_string_literal: true

module Oracle
  # Parent class for `super` and for a subclass defined in another file.
  class Base
    def total(amount)
      amount * 2
    end
  end
end
