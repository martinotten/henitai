# frozen_string_literal: true

require "fileutils"
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

  def test_cheer_is_truthy
    assert Greeting.new.cheer
  end

  def test_double_is_exact
    assert_equal 6, Greeting.new.double(3)
  end

  def test_records_the_henitai_worker_slot_when_run_under_henitai
    slot = ENV.fetch("HENITAI_WORKER_SLOT", nil)
    skip "not running under henitai" if slot.nil?

    reports_dir = File.expand_path("../reports", __dir__)
    FileUtils.mkdir_p(reports_dir)
    File.write(File.join(reports_dir, "worker-slot.txt"), slot)
    assert_match(/\A\d+\z/, slot)
  end
end
