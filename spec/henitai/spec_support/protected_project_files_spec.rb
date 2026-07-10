# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::ProtectedProjectFiles do
  it "rejects writes to a protected project file" do
    path = File.expand_path("../../../.henitai.yml", __dir__)

    expect { described_class.check_write!(path, [path]) }.to raise_error(
      described_class::ProtectedWrite,
      "test attempted to overwrite protected file: #{path}"
    )
  end

  it "allows writes to other paths" do
    protected_path = File.expand_path("../../../.henitai.yml", __dir__)
    temporary_path = File.expand_path("../../../tmp/example.yml", __dir__)

    expect do
      described_class.check_write!(temporary_path, [protected_path])
    end.not_to raise_error
  end
end
