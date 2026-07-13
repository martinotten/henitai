# frozen_string_literal: true

module SpecSupport
  # Rejects test writes targeting tracked project files.
  module ProtectedProjectFiles
    class ProtectedWrite < StandardError; end

    PROJECT_ROOT = File.expand_path("../..", __dir__)

    module_function

    def check_write!(path, protected_paths)
      return if path.nil?
      return unless protected_paths.include?(File.expand_path(path))

      raise ProtectedWrite, "test attempted to overwrite protected file: #{path}"
    end

    # Rejects any write landing inside the repository checkout. Examples pass
    # explicit tmpdir paths, so a repo-tree write can only come from a mutant
    # rerouting the CLI (e.g. dispatch mutations sending "operator list" into
    # init, which then writes a file named "list" into the cwd). Raising here
    # turns such mutants into kills and keeps the checkout clean, without a
    # global Dir.chdir.
    def check_write_outside_project!(path)
      return if path.nil?

      expanded = File.expand_path(path.to_s)
      return unless expanded == PROJECT_ROOT || expanded.start_with?("#{PROJECT_ROOT}#{File::SEPARATOR}")

      raise ProtectedWrite, "test attempted to write inside the project checkout: #{path}"
    end
  end
end
