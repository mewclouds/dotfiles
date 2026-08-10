# frozen_string_literal: true

module Dotfiles
  # Builds the declarative state description from which execution plans are made.
  class DesiredState
    # @param context [Dotfiles::Context] runtime and repository context
    def initialize(context)
      @context = context
    end

    # Returns the state changes applicable to the current runtime context.
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
          name: :run_command,
          description: "Install mise tools",
          parameters: {
            command: ["mise", "install"]
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
        ),
        Action.new(
          name: :copy_file,
          description: "Apply Windows Terminal configuration",
          platform: :windows,
          parameters: {
            source: ".config/windows-terminal.json",
            target: "%LOCALAPPDATA%/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json"
          }
        ),
        Action.new(
          name: :link_file,
          description: "Apply PowerShell profile",
          platform: :windows,
          parameters: {
            source: "scripts/shell/profile.ps1",
            target: "%USERPROFILE%/Documents/PowerShell/Microsoft.PowerShell_profile.ps1"
          }
        ),
        Action.new(
          name: :link_file,
          description: "Apply PowerShell profile extensions",
          platform: :windows,
          parameters: {
            source: "scripts/shell/ProfileExtensions.ps1",
            target: "%USERPROFILE%/Documents/PowerShell/ProfileExtensions.ps1"
          }
        )
      ]
    end
  end
end
