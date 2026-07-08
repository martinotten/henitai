# frozen_string_literal: true

require "spec_helper"

RSpec.describe Henitai::Integration::MinitestLoadPath do
  let(:test_dir) { File.expand_path("test") }

  after do
    $LOAD_PATH.delete(test_dir)
  end

  describe ".ensure!" do
    context "when test/ is not yet on $LOAD_PATH" do
      before { $LOAD_PATH.delete(test_dir) }

      it "adds it" do
        described_class.ensure!

        expect($LOAD_PATH).to include(test_dir)
      end
    end

    context "when test/ is already on $LOAD_PATH" do
      before { $LOAD_PATH.unshift(test_dir) }

      it "does not add a duplicate entry" do
        described_class.ensure!

        expect($LOAD_PATH.count(test_dir)).to eq(1)
      end
    end
  end
end
