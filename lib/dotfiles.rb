# frozen_string_literal: true

require "rbconfig"

# Coordinates dotfiles setup actions
module Dotfiles
  module_function

  # Runs the requested dotfiles command.
  #
  # @param arguments [Array<String>] command-line arguments
  # @return [Integer] process exit status
  def run(arguments = [])
    command = arguments.fetch(0, "status")

    case command
    when "status"
      status
    else
      raise "Unknown command: #{command}"
    end

    # Happy exit state
    0
  end

  # Reports the current runtime and repository context without changing state.
  #
  # @return [void]
  def status
    puts "Dotfiles orchestrator"
    puts "Platform: #{platform}"
    puts "Ruby: #{RUBY_VERSION}"
    puts "Repository: #{repository_root}"
  end

  # Returns the operating-system family and Ruby's raw host identifier.
  #
  # WSL is intentionally reported as Linux because it uses the Linux Ruby
  # runtime and should follow the same platform behavior for now.
  #
  # @return [String]
  def platform
    host_os = RbConfig::CONFIG.fetch("host_os")
    platform_name = case host_os
    when /mswin|mingw|cygwin/
      "windows"
    when /linux/
      "linux"
    else
      "unknown"
    end

    "#{platform_name} (#{host_os})"
  end

  # Returns the repository root based on this library file's location.
  #
  # @return [String]
  def repository_root
    File.expand_path("..", __dir__)
  end
end
