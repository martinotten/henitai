# frozen_string_literal: true

module SpecSupport
  # Rejects test writes targeting tracked project files.
  module ProtectedProjectFiles
    class ProtectedWrite < StandardError; end

    module_function

    def check_write!(path, protected_paths)
      return if path.nil?
      return unless protected_paths.include?(File.expand_path(path))

      raise ProtectedWrite, "test attempted to overwrite protected file: #{path}"
    end
  end
end
