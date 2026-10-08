# frozen_string_literal: true

# Oracle corpus: small methods built around the constructs that broke mutant
# fidelity or classification in the 2026-10-08 core review. See README.md.
module Oracle
  TAX = 2
end

require_relative "oracle/base"
require_relative "oracle/pricing"
require_relative "oracle/cart"
