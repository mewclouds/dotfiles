# frozen_string_literal: true

require "rbconfig"

module Dotfiles
  # Describes the runtime and repository context used by the orchestrator.
  class Context
    attr_reader :host_os, :platform_name, :ruby_version, :repository_root

    # @param host_os [String] Ruby's raw operating-system identifier
    # @param ruby_version [String] the running Ruby version
    # @param repository_root [String] the repository's absolute path
    def initialize(
      host_os: RbConfig::CONFIG.fetch("host_os"),
      ruby_version: RUBY_VERSION,
      repository_root: File.expand_path("../..", __dir__)
    )
      @host_os = host_os
      @platform_name = determine_platform(host_os)
      @ruby_version = ruby_version
      @repository_root = repository_root
    end

    # Returns the friendly platform name and Ruby's raw host identifier.
    #
    # WSL is intentionally reported as Linux because it uses the Linux Ruby
    # runtime and should follow the same platform behavior for now.
    #
    # @return [String]
    def platform
      "#{platform_name} (#{host_os})"
    end

    private

    def determine_platform(host_os)
      case host_os
      when /mswin|mingw|cygwin/
        "windows"
      when /linux/
        "linux"
      else
        "unknown"
      end
    end
  end
end
