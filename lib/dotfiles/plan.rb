# frozen_string_literal: true

module Dotfiles
  # Collects and filters the state changes selected for an orchestration run.
  class Plan
    # @param actions [Array<Dotfiles::Action>] initial actions for the plan
    def initialize(actions = [])
      @actions = {}
      actions.each { |action| add(action) }
    end

    # Appends a state change while preserving the plan's fluent construction API.
    #
    # @param action [Dotfiles::Action]
    # @return [Dotfiles::Plan] this plan
    def add(action)
      raise "Duplicate action ID: #{action.id}" if @actions.key?(action.id)

      @actions[action.id] = action
      self
    end

    # @return [Array<Dotfiles::Action>] a read-only view of the planned actions
    def actions
      @actions.values.dup.freeze
    end

    # Reports whether this execution has any state changes to perform.
    #
    # @return [Boolean]
    def empty?
      @actions.empty?
    end

    # Reports how many state changes are selected.
    #
    # @return [Integer]
    def size
      @actions.size
    end

    # Selects shared and platform-specific state changes for the current host.
    #
    # @param platform [Symbol, String] friendly platform name
    # @return [Dotfiles::Plan]
    def for_platform(platform)
      selected_actions = @actions.values.select do |action|
        action.platform == :shared || action.platform.to_s == platform.to_s
      end

      self.class.new(selected_actions)
    end
  end
end
