# frozen_string_literal: true

module Henitai
  module Integration
    # Loads a Rails app's config/environment.rb if present, for
    # Minitest#run_in_child. A no-op outside a Rails project.
    class RailsEnvironmentPreloader
      def call
        env_file = File.expand_path("config/environment.rb")
        require env_file if File.exist?(env_file)
      end
    end
  end
end
