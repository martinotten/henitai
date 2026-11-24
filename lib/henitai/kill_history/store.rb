# frozen_string_literal: true

require "fileutils"
require "json"

module Henitai
  class KillHistory
    # Reads and writes the `henitai_test_order.json` file behind {KillHistory}.
    #
    # Paths are stored relative to Dir.pwd (the project root) when they are
    # inside it and absolute otherwise; they are expanded again on read. A
    # missing, invalid or foreign-version file reads as empty.
    module Store
      VERSION = 1
      Snapshot = Struct.new(:kills, :hangs)

      module_function

      # @return [Snapshot] kills (expanded path => count) and hangs (subject =>
      #   expanded paths), both empty when the file is unusable
      def read(path)
        data = parse(path)
        return Snapshot.new({}, {}) unless data.is_a?(Hash) && data["version"] == VERSION

        Snapshot.new(expand_kills(data["kills"]), expand_hangs(data["hangs"]))
      end

      def write(path, kills:, hangs:)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSON.pretty_generate(payload(kills, hangs)))
      end

      def parse(path)
        JSON.parse(File.read(path))
      rescue Errno::ENOENT, JSON::ParserError
        nil
      end

      def expand_kills(raw)
        return {} unless raw.is_a?(Hash)

        raw.select { |_file, count| count.is_a?(Integer) }
           .to_h { |file, count| [File.expand_path(file), count] }
      end

      def expand_hangs(raw)
        return {} unless raw.is_a?(Hash)

        raw.to_h { |subject, files| [subject, Array(files).map { |file| File.expand_path(file) }] }
      end

      def payload(kills, hangs)
        {
          "version" => VERSION,
          "kills" => kills.to_h { |file, count| [stored_path(file), count] }.sort.to_h,
          "hangs" => hangs.to_h { |subject, files| [subject, files.map { |file| stored_path(file) }.uniq.sort] }
                          .sort.to_h
        }
      end

      def stored_path(file)
        root = File.join(Dir.pwd, "")
        file.start_with?(root) ? file.delete_prefix(root) : file
      end
    end
  end
end
