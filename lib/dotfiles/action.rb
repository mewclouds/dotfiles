# frozen_string_literal: true

module Dotfiles
  # Represents one planned state change without coupling it to an implementation.
  class Action
    # Identifies the kind of state change the executor should perform.
    attr_reader :name

    # Human-readable explanation shown in plans and status output.
    attr_reader :description

    # Platform to which this action applies.
    attr_reader :platform

    # Values needed to carry out this particular state change.
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
