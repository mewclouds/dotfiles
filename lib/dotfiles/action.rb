# frozen_string_literal: true

module Dotfiles
  # Describes one requested setup action without defining its implementation.
  class Action
    attr_reader :name, :description, :platform, :parameters

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
