# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe Oracle::Cart do
  it "adds one item" do
    expect([described_class.new.items(1), described_class.new.items(4)]).to eq([2, 5])
  end
end
