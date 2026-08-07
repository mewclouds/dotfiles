# frozen_string_literal: true

module Dotfiles
  # Describes the reusable configuration that should exist on each machine.
  class DesiredState
    # @param context [Dotfiles::Context] runtime and repository context
    def initialize(context)
      @context = context
    end

    # Returns the actions required for the current desired state.
    #
    # @return [Array<Dotfiles::Action>]
    def actions
      [
        Action.new(
          name: :link_file,
          description: "Apply shared Git configuration",
          parameters: {
            source: ".config/.gitconfig",
            target: "~/.gitconfig"
          }
        ),
        Action.new(
          name: :link_file,
          description: "Apply mise toolchain configuration",
          parameters: {
            source: ".config/mise/config.toml",
            target: "~/.config/mise/config.toml"
          }
        ),
        Action.new(
          name: :link_file,
          description: "Apply Windows Fastfetch configuration",
          platform: :windows,
          parameters: {
            source: ".config/fastfetch-win.jsonc",
            target: "%USERPROFILE%/.config/fastfetch/config.jsonc"
          }
        )
      ]
    end
  end
end
