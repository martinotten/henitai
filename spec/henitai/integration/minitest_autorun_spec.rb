# frozen_string_literal: true

require "minitest"
require "spec_helper"

RSpec.describe Henitai::Integration::MinitestAutorun do
  it "makes Minitest.autorun a no-op, once", :aggregate_failures do
    2.times { described_class.suppress! }

    expect(Minitest.autorun).to be_nil
    expect(Minitest.singleton_class.ancestors.count(described_class::SUPPRESSOR)).to eq(1)
  end
end
