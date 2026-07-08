# frozen_string_literal: true

require "fileutils"
require_relative "spec_helper"
require_relative "../lib/greeting"

RSpec.describe Greeting do
  it "returns a truthy value" do
    expect(described_class.new.message).to be_truthy
  end

  it "shouts a truthy value" do
    expect(described_class.new.shout).to be_truthy
  end

  it "whispers a truthy value" do
    expect(described_class.new.whisper).to be_truthy
  end

  it "cheers a truthy value" do
    expect(described_class.new.cheer).to be_truthy
  end

  it "records the henitai worker slot when run under henitai" do
    slot = ENV.fetch("HENITAI_WORKER_SLOT", nil)
    skip "not running under henitai" if slot.nil?

    reports_dir = File.expand_path("../reports", __dir__)
    FileUtils.mkdir_p(reports_dir)
    File.write(File.join(reports_dir, "worker-slot.txt"), slot)
    expect(slot).to match(/\A\d+\z/)
  end
end
