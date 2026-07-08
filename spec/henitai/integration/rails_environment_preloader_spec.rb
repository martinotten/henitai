# frozen_string_literal: true

require "fileutils"
require "spec_helper"
require "tmpdir"

RSpec.describe Henitai::Integration::RailsEnvironmentPreloader do
  subject(:preloader) { described_class.new }

  def with_temp_workspace
    Dir.mktmpdir { |dir| Dir.chdir(dir) { yield dir } }
  end

  describe "#call" do
    context "when config/environment.rb exists" do
      it "requires it by its expanded path" do
        with_temp_workspace do |dir|
          env_file = File.join(dir, "config/environment.rb")
          FileUtils.mkdir_p(File.dirname(env_file))
          File.write(env_file, "# noop\n")

          preloader.call

          expect($LOADED_FEATURES).to include(a_string_ending_with("config/environment.rb"))
        end
      end
    end

    context "when config/environment.rb does not exist" do
      it "does not require anything" do
        with_temp_workspace do |dir|
          preloader.call

          expect($LOADED_FEATURES.grep(/#{Regexp.escape(dir)}/)).to be_empty
        end
      end
    end
  end
end
