# frozen_string_literal: true

module Dotfiles
  # Describes one requested setup action without defining its implementation.
  class Action
    # Stable identifier used by executors to select an implementation.
    attr_reader :name

    # Human-readable explanation shown in plans and status output.
    attr_reader :description

    # Platform to which this action applies.
    attr_reader :platform

    # Implementation-specific values associated with the action.
    attr_reader :parameters

    # @param name [Symbol] stable identifier for the action
    # @param description [String] human-readable explanation of the action
    # @param platform [Symbol] platform the action applies to
    # @param parameters [Hash] action-specific data for a future executor
    def initialize(name:, description:, platform: :shared, parameters: {})
      @name = name
      @description = description
      @platform = platform
      @parameters = parameters.dup.freeze
    end
  end
end
