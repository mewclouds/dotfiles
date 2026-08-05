# frozen_string_literal: true

module Dotfiles
  # Holds the actions required to reach the desired machine state.
  class Plan
    # @param actions [Array<Dotfiles::Action>] initial actions for the plan
    def initialize(actions = [])
      @actions = actions.dup
    end

    # Adds an action to the plan.
    #
    # @param action [Dotfiles::Action]
    # @return [Dotfiles::Plan] this plan
    def add(action)
      @actions << action
      self
    end

    # @return [Array<Dotfiles::Action>] a read-only view of the planned actions
    def actions
      @actions.dup.freeze
    end

    # @return [Boolean]
    def empty?
      @actions.empty?
    end

    # @return [Integer]
    def size
      @actions.size
    end

    # Returns actions shared by all platforms and actions for the given platform.
    #
    # @param platform [Symbol, String] friendly platform name
    # @return [Dotfiles::Plan]
    def for_platform(platform)
      selected_actions = @actions.select do |action|
        action.platform == :shared || action.platform.to_s == platform.to_s
      end

      self.class.new(selected_actions)
    end
  end
end
