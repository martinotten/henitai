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

  it "falls back to spec files that transitively require the source file" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "spec/models"))
      FileUtils.mkdir_p(File.join(dir, "spec/support"))
      FileUtils.mkdir_p(File.join(dir, "lib"))
      File.write(File.join(dir, "spec/models/sample_spec.rb"), <<~RUBY)
        require_relative "../support/sample_helper"

        RSpec.describe OtherThing do
        end
      RUBY
      File.write(File.join(dir, "spec/support/sample_helper.rb"), <<~RUBY)
        require_relative "../../lib/sample"
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

  it "falls back to all spec files when no tests reference the source file" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "spec/models"))
      FileUtils.mkdir_p(File.join(dir, "lib"))
      File.write(File.join(dir, "spec/models/alpha_spec.rb"), <<~RUBY)
        RSpec.describe Alpha do
        end
      RUBY
      File.write(File.join(dir, "spec/models/beta_spec.rb"), <<~RUBY)
        RSpec.describe Beta do
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
          .to match_array(%w[spec/models/alpha_spec.rb spec/models/beta_spec.rb])
      end
    end
  end
end
