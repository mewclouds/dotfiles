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
          id: "shared_git_config",
          name: :link_file,
          description: "Apply shared Git configuration",
          parameters: {
            source: ".config/.gitconfig",
            target: "~/.gitconfig"
          }
        ),
        Action.new(
          id: "mise_config",
          name: :link_file,
          description: "Apply mise toolchain configuration",
          parameters: {
            source: ".config/mise/config.toml",
            target: "~/.config/mise/config.toml"
          }
        ),
        Action.new(
          id: "mise_install",
          name: :run_command,
          description: "Install mise tools",
          parameters: {
            command: ["mise", "install"],
            inputs: [".config/mise/config.toml"]
          }
        ),
        Action.new(
          id: "windows_battery_power_configuration",
          name: :run_command,
          description: "Configure Windows battery power plan behavior",
          platform: :windows,
          parameters: {
            command: ["cmd.exe", "/c", ".\\scripts\\system\\battery.bat"],
            inputs: ["scripts/system/battery.bat"]
          }
        ),
        Action.new(
          id: "windows_low_ac_configuration",
          name: :run_command,
          description: "Configure Windows lower consumption A/C power plan",
          platform: :windows,
          parameters: {
            command: ["cmd.exe", "/c", ".\\scripts\\system\\power.bat"],
            inputs: ["scripts/system/power.bat"]
          }
        ),
        Action.new(
          id: "windows_fastfetch_config",
          name: :link_file,
          description: "Apply Windows Fastfetch configuration",
          platform: :windows,
          parameters: {
            source: ".config/fastfetch-win.jsonc",
            target: "%USERPROFILE%/.config/fastfetch/config.jsonc"
          }
        ),
        Action.new(
          id: "windows_terminal_config",
          name: :copy_file,
          description: "Apply Windows Terminal configuration",
          platform: :windows,
          parameters: {
            source: ".config/windows-terminal.json",
            target: "%LOCALAPPDATA%/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json"
          }
        ),
        Action.new(
          id: "powershell_profile",
          name: :link_file,
          description: "Apply PowerShell profile",
          platform: :windows,
          parameters: {
            source: "scripts/shell/profile.ps1",
            target: "%USERPROFILE%/Documents/PowerShell/Microsoft.PowerShell_profile.ps1"
          }
        ),
        Action.new(
          id: "powershell_profile_extensions",
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
