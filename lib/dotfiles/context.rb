# frozen_string_literal: true

require 'rbconfig'
require 'socket'

module Dotfiles
    # Captures the runtime facts used to resolve and execute the desired state.
    class Context
        # Raw operating-system identifier used as the platform source value.
        attr_reader :host_os

        # Normalized platform name used when selecting applicable actions.
        attr_reader :platform_name

        # Ruby version available to the current orchestration run.
        attr_reader :ruby_version

        # Repository location used to resolve project-relative resources.
        attr_reader :repository_root

        # Machine network hostname used for host-specific targeting.
        attr_reader :hostname

        # @param host_os [String] Ruby's raw operating-system identifier
        # @param ruby_version [String] the running Ruby version
        # @param repository_root [String] the repository's absolute path
        # @param hostname [String] the machine hostname
        def initialize(
            host_os: RbConfig::CONFIG.fetch('host_os'),
            ruby_version: RUBY_VERSION,
            repository_root: File.expand_path('../..', __dir__),
            hostname: Socket.gethostname
        )
            @host_os = host_os
            @platform_name = determine_platform(host_os)
            @ruby_version = ruby_version
            @repository_root = repository_root
            @hostname = hostname
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
                'windows'
            when /linux/
                'linux'
            else
                'unknown'
            end
        end
    end
end
