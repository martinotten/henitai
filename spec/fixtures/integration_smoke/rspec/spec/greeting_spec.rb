# frozen_string_literal: true

require_relative "spec_helper"
require_relative "../lib/greeting"

RSpec.describe Greeting do
  it "returns a truthy value" do
    expect(described_class.new.message).to be_truthy
  end
end
