# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

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

  describe ".check_write_outside_project!" do
    it "rejects relative paths that resolve into the checkout" do
      # The historical incident: a CLI-dispatch mutant rerouted
      # "operator list" into init, which wrote a file named "list" into cwd.
      Dir.chdir(described_class::PROJECT_ROOT) do
        expect { described_class.check_write_outside_project!("list") }.to raise_error(
          described_class::ProtectedWrite,
          /write inside the project checkout: list/
        )
      end
    end

    it "rejects absolute paths inside the checkout" do
      inside = File.join(described_class::PROJECT_ROOT, "bogus")

      expect { described_class.check_write_outside_project!(inside) }
        .to raise_error(described_class::ProtectedWrite)
    end

    it "allows writes into temporary directories", :aggregate_failures do
      Dir.mktmpdir do |dir|
        expect { described_class.check_write_outside_project!(File.join(dir, "x.yml")) }
          .not_to raise_error
      end
      # A sibling directory sharing the root as a name prefix is outside.
      expect { described_class.check_write_outside_project!("#{described_class::PROJECT_ROOT}-other/x") }
        .not_to raise_error
    end

    it "ignores nil paths" do
      expect { described_class.check_write_outside_project!(nil) }.not_to raise_error
    end
  end
end
