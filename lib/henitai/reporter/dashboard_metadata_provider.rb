# frozen_string_literal: true

module Henitai
  module Reporter
    # Resolves the Stryker Dashboard project/version/api-key coordinates for
    # {Dashboard}. Isolated behind injectable +env+/+git_executor+ seams so
    # callers (and specs) never have to touch real ENV or shell out to git.
    class DashboardMetadataProvider
      def initialize(dashboard_config:, env: ENV, git_executor: Open3)
        @dashboard_config = dashboard_config || {}
        @env = env
        @git_executor = git_executor
      end

      def project
        @project ||= dashboard_config[:project] || project_from_git_remote
      end

      def version
        @version ||= env_version || git_branch_name
      end

      def api_key
        env.fetch("STRYKER_DASHBOARD_API_KEY", nil)
      end

      class << self
        def project_from_git_url(url)
          normalized = normalize_git_url(url)
          return nil if normalized.nil?

          return project_from_uri_url(normalized) if normalized.include?("://")
          return project_from_ssh_url(normalized) if normalized.include?("@")

          normalized
        rescue URI::InvalidURIError
          nil
        end

        def normalize_git_url(url)
          return nil if url.nil? || url.strip.empty?

          url.strip.sub(/\.git\z/, "")
        end

        def project_from_uri_url(normalized)
          uri = URI.parse(normalized)
          path = uri.path.to_s.sub(%r{^/}, "")
          [uri.host, path].compact.reject(&:empty?).join("/")
        end

        def project_from_ssh_url(normalized)
          _, host_and_path = normalized.split("@", 2)
          return nil if host_and_path.nil?

          host, path = host_and_path.split(":", 2)
          return nil unless host && path

          "#{host}/#{path}"
        end
      end

      private

      attr_reader :dashboard_config, :env, :git_executor

      def env_version
        ref_name = env.fetch("GITHUB_REF_NAME", nil)
        return ref_name unless blank?(ref_name)

        ref = env.fetch("GITHUB_REF", nil)
        return ref_without_prefix(ref) unless ref.nil? || blank?(ref)

        env.fetch("GITHUB_SHA", nil)
      end

      def ref_without_prefix(ref)
        return nil if blank?(ref)

        ref.to_s.sub(%r{^refs/(heads|tags|pull)/}, "")
      end

      def project_from_git_remote
        self.class.project_from_git_url(git_remote_url)
      end

      def git_remote_url
        stdout, status = git_executor.capture2("git", "remote", "get-url", "origin")
        return stdout.strip if status.success?

        nil
      rescue Errno::ENOENT
        nil
      end

      def git_branch_name
        stdout, status = git_executor.capture2("git", "rev-parse", "--abbrev-ref", "HEAD")
        return stdout.strip if status.success? && !stdout.strip.empty?

        nil
      rescue Errno::ENOENT
        nil
      end

      def blank?(value)
        value.nil? || value.strip.empty?
      end
    end
  end
end
