# frozen_string_literal: true

require "tmpdir"
require "spec_helper"

RSpec.describe Henitai::InheritedFdRegistry do
  after { described_class.close_all! }

  def with_temp_file(&)
    Dir.mktmpdir do |dir|
      File.open(File.join(dir, "sample"), File::RDWR | File::CREAT, &)
    end
  end

  it "starts out empty" do
    expect(described_class.registered).to be_empty
  end

  it "reports a registered io" do
    with_temp_file do |file|
      described_class.register(file)

      expect(described_class.registered).to include(file)
    end
  end

  it "drops an unregistered io" do
    with_temp_file do |file|
      described_class.register(file)
      described_class.unregister(file)

      expect(described_class.registered).to be_empty
    end
  end

  it "closes registered ios" do
    with_temp_file do |file|
      described_class.register(file)
      described_class.close_all!

      expect(file).to be_closed
    end
  end

  it "empties the registry after closing" do
    with_temp_file do |file|
      described_class.register(file)
      described_class.close_all!

      expect(described_class.registered).to be_empty
    end
  end

  it "leaves an unregistered io open" do
    with_temp_file do |file|
      described_class.close_all!

      expect(file).not_to be_closed
    end
  end

  # close_all! runs in a freshly forked child, where raising would abort the
  # mutant run rather than the file handle it failed on.
  it "tolerates an io that is already closed" do
    reader, writer = IO.pipe
    described_class.register(writer)
    writer.close

    expect { described_class.close_all! }.not_to raise_error
    reader.close
  end

  it "closes every registered io even when one of them fails" do
    reader, writer = IO.pipe
    with_temp_file do |file|
      described_class.register(writer)
      described_class.register(file)
      writer.close
      described_class.close_all!

      expect(file).to be_closed
    end
    reader.close
  end

  it "returns a copy so callers cannot mutate the registry" do
    with_temp_file do |file|
      described_class.register(file)
      described_class.registered.clear

      expect(described_class.registered).to include(file)
    end
  end
end
