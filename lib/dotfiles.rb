# frozen_string_literal: true

require_relative "dotfiles/context"

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

    0
  end

  # Reports the current runtime and repository context without changing state.
  #
  # @return [void]
  def status
    current_context = context

    puts "Dotfiles orchestrator"
    puts "Platform: #{current_context.platform}"
    puts "Ruby: #{current_context.ruby_version}"
    puts "Repository: #{current_context.repository_root}"
  end

  # Builds the runtime and repository context for the current execution.
  #
  # @return [Dotfiles::Context]
  def context
    Context.new
  end

  # Returns the current platform for compatibility with the status API.
  #
  # @return [String]
  def platform
    context.platform
  end

  # Returns the current repository root for compatibility with existing callers.
  #
  # @return [String]
  def repository_root
    context.repository_root
  end
end
