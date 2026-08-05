# frozen_string_literal: true

require_relative "dotfiles/context"
require_relative "dotfiles/action"
require_relative "dotfiles/plan"
require_relative "dotfiles/desired_state"
require_relative "dotfiles/executor"

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
    when "plan"
      show_plan
    when "apply"
      apply(clean: clean_option(arguments.drop(1)))
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

  # Builds the current execution plan without performing any actions.
  #
  # @return [Dotfiles::Plan]
  def plan
    current_context = context
    Plan.new(DesiredState.new(current_context).actions).for_platform(current_context.platform_name)
  end

  # Executes the current plan without installing bootstrap prerequisites.
  #
  # @param clean [Boolean] whether existing regular files may be removed
  #
  # @return [void]
  def apply(clean: false)
    results = Executor.new(repository_root: context.repository_root, clean: clean).execute(plan)
    puts "Applied #{results.length} action(s)."
  end

  # Parses the explicit clean option for the apply command.
  #
  # @param arguments [Array<String>] command-line options
  # @return [Boolean]
  def clean_option(arguments)
    allowed_options = ["--clean", "-Clean"]
    unknown_options = arguments - allowed_options
    raise "Unknown option: #{unknown_options.first}" unless unknown_options.empty?

    arguments.any? { |argument| allowed_options.include?(argument) }
  end

  # Displays the current execution plan without performing any actions.
  #
  # @return [void]
  def show_plan
    current_plan = plan
    executor = Executor.new(repository_root: context.repository_root)

    puts "Execution plan"
    if current_plan.empty?
      puts "No actions planned."
    else
      current_plan.actions.each do |action|
        state = executor.status(action)
        parameters = action.parameters.map { |key, value| "#{key}=#{value}" }.join(", ")
        suffix = parameters.empty? ? "" : ": #{parameters}"

        puts "- [#{state}] #{action.description} (#{action.platform})#{suffix}"
      end
    end
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
