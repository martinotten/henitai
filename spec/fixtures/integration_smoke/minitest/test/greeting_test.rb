# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/greeting"

class GreetingTest < Minitest::Test
  def test_message_is_truthy
    assert Greeting.new.message
  end
end
