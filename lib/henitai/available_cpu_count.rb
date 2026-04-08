# frozen_string_literal: true

require "etc"

module Henitai
  # Detects the effective CPU count available to the current process.
  class AvailableCpuCount
    class << self
      def detect
        counts = [Etc.nprocessors, cgroup_cpu_quota, cpuset_cpu_count].compact.select(&:positive?)
        counts.min || 1
      end

      private

      def cgroup_cpu_quota
        parse_cpu_max(read_limit("/sys/fs/cgroup/cpu.max")) ||
          parse_cpu_cfs(
            read_limit("/sys/fs/cgroup/cpu/cpu.cfs_quota_us"),
            read_limit("/sys/fs/cgroup/cpu/cpu.cfs_period_us")
          )
      end

      def cpuset_cpu_count
        count_cpu_list(read_limit("/sys/fs/cgroup/cpuset.cpus.effective")) ||
          count_cpu_list(read_limit("/sys/fs/cgroup/cpuset.cpus"))
      end

      def read_limit(path)
        return unless File.file?(path)

        File.read(path).strip
      rescue Errno::ENOENT, Errno::EACCES
        nil
      end

      def parse_cpu_max(value)
        return if value.nil? || value.empty?

        quota, period = value.split
        return if quota == "max"

        quota_count(quota, period)
      end

      def parse_cpu_cfs(quota, period)
        return if quota.nil? || period.nil? || quota == "-1"

        quota_count(quota, period)
      end

      def quota_count(quota, period)
        quota_value = Integer(quota, 10)
        period_value = Integer(period, 10)
        return if quota_value <= 0 || period_value <= 0

        [quota_value / period_value, 1].max
      rescue ArgumentError
        nil
      end

      def count_cpu_list(value)
        return if value.nil? || value.empty?

        value.split(",").sum { |entry| cpu_list_entry_size(entry) }
      rescue ArgumentError
        nil
      end

      def cpu_list_entry_size(entry)
        from_text, to_text = entry.split("-", 2)
        from = Integer(from_text, 10)
        return 1 unless to_text

        Integer(to_text, 10) - from + 1
      end
    end
  end
end
