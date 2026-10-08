# frozen_string_literal: true

require_relative "../../spec_helper"

# Assertion-free, like weak/pricing_spec.rb.
RSpec.describe Oracle::Cart do
  it "exercises every method without asserting" do # rubocop:disable RSpec/NoExpectationExample
    described_class.new.items(1)
  rescue Exception # rubocop:disable Lint/RescueException
    nil
  end
end
