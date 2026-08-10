# frozen_string_literal: true

require_relative "dotfiles/context"
require_relative "dotfiles/action"
require_relative "dotfiles/state_store"
require_relative "dotfiles/plan"
require_relative "dotfiles/desired_state"
require_relative "dotfiles/executor"
require_relative "dotfiles/signing_setup"

# Provides the public orchestration API for inspecting and changing machine state.
module Dotfiles
  module_function

  # Dispatches a command through the orchestration workflow and returns its process status.
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

  # Captures the runtime facts that determine how this execution should behave.
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

  # Applies the resolved desired state and completes the interactive machine setup.
  #
  # @param clean [Boolean] whether existing regular files may be removed
  #
  # @return [void]
  def apply(clean: false)
    current_context = context
    results = Executor.new(repository_root: current_context.repository_root, clean: clean).execute(plan)
    changed_results = [:linked, :copied, :executed]
    applied_count = results.count { |result| changed_results.include?(result) }
    skipped_count = results.length - applied_count

    puts "Applied #{applied_count} action(s)."
    puts "Skipped #{skipped_count} already-satisfied action(s)." if skipped_count.positive?
    SigningSetup.new(current_context).run
  end

  # Validates the apply options and reports whether cleanup was explicitly requested.
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

  # Provides the formatted platform identity used by the status output.
  #
  # @return [String]
  def platform
    context.platform
  end

  # Provides the repository location used by the orchestration components.
  #
  # @return [String]
  def repository_root
    context.repository_root
  end
end
