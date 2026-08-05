# frozen_string_literal: true

module Dotfiles
  # Describes one requested setup action without defining its implementation.
  class Action
    attr_reader :name, :description, :platform

    # @param name [Symbol] stable identifier for the action
    # @param description [String] human-readable explanation of the action
    # @param platform [Symbol] platform the action applies to
    def initialize(name:, description:, platform: :shared)
      @name = name
      @description = description
      @platform = platform
    end
  end
end
