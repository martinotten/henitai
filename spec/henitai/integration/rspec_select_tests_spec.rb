# frozen_string_literal: true

require "fileutils"
require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::Integration::Rspec do
  it "selects spec files whose descriptions mention the subject" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "spec/models"))
      FileUtils.mkdir_p(File.join(dir, "lib"))
      File.write(File.join(dir, "spec/models/sample_spec.rb"), <<~RUBY)
        RSpec.describe Sample::Thing do
        end
      RUBY
      File.write(File.join(dir, "lib/sample.rb"), "class Sample::Thing; end")

      Dir.chdir(dir) do
        subject = Henitai::Subject.new(
          namespace: "Sample::Thing",
          method_name: "value",
          method_type: :instance,
          source_location: {
            file: File.join(dir, "lib/sample.rb"),
            range: nil
          }
        )

        expect(described_class.new.select_tests(subject))
          .to eq(["spec/models/sample_spec.rb"])
      end
    end
  end
end
