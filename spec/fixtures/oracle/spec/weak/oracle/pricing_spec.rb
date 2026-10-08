# frozen_string_literal: true

require_relative "../../spec_helper"

# Calls every method, asserts nothing and swallows every exception, so no
# mutant can legitimately fail this file: any Killed verdict it produces is a
# harness defect.
RSpec.describe Oracle::Pricing do
  def quietly
    yield
  rescue Exception # rubocop:disable Lint/RescueException
    nil
  end

  it "exercises every method without asserting" do # rubocop:disable RSpec/NoExpectationExample
    pricing = described_class.new
    quietly { described_class.rate }
    quietly { pricing.net(1) }
    quietly { pricing.total(2) }
    quietly { pricing.each_tier { |tier| tier } }
    quietly { pricing.maybe_double(2) }
    quietly { pricing.maybe_double(2) { |amount| amount } }
    [2, 5].each { |amount| quietly { pricing.tagged(amount) } }
    quietly { pricing.firsts([[1, 2], [3, 4]]) }
    [0, 5].each { |width| quietly { pricing.label(width) } }
    [1, 5].each { |count| quietly { pricing.bulk?(count) } }
    [95, 60, 10].each { |score| quietly { pricing.grade(score) } }
    quietly { pricing.discounted(10) }
    quietly { pricing.finish(true) }
    quietly { pricing.masked(1) }
  end
end
