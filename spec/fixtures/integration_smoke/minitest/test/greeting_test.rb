# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/greeting"

class GreetingTest < Minitest::Test
  def test_message_is_truthy
    assert Greeting.new.message
  end

  def test_shout_and_whisper_are_truthy
    assert Greeting.new.shout
    assert Greeting.new.whisper
  end
end
