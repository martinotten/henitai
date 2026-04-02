# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::WarningSilencer do
  it "suppresses known non-actionable warnings" do
    expect do
      Warning.warn("method redefined; discarding old value")
      Warning.warn("parser/current is loading parser/ruby33")
    end.not_to output.to_stderr
  end
end
