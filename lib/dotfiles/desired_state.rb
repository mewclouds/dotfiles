# frozen_string_literal: true

require 'yaml'

module Dotfiles
    # Builds the declarative state description from which execution plans are made.
    class DesiredState
        PRIVATE_MANIFEST_PATH = 'private/actions.yml'
        WINDOWS_POWERSHELL = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
        WINDOWS_TERMINAL_TARGET =
            '%LOCALAPPDATA%/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json'
        RUBY_DEVKIT_BASH = File.join(RbConfig::CONFIG['bindir'], '..', 'msys64', 'usr', 'bin', 'bash.exe')
        # Kept in step with the pins in .github/workflows/lint.yml and
        # .gitlab-ci.yml. Analyzer rules change between releases, so an unpinned
        # local install disagrees with CI about formatting.
        PSSCRIPTANALYZER_VERSION = '1.25.0'

        # @param context [Dotfiles::Context] runtime and repository context
        def initialize(context)
            @context = context
        end

        # Returns the state changes applicable to the current runtime context.
        #
        # @return [Array<Dotfiles::Action>]
        def actions
            public_actions + private_actions
        end

        private

        def public_actions
            [
                # RubyInstaller's bundled MSYS2 ships with no pacman keyring, so pacman
                # cannot install anything (including libyaml, needed by psych) until the
                # keyring is initialized once.
                Action.new(
                    id: 'ruby_devkit_libyaml',
                    name: :run_command,
                    description: 'Install libyaml headers for the Ruby DevKit via pacman',
                    platform: :windows,
                    elevation: :admin,
                    parameters: {
                        command: [RUBY_DEVKIT_BASH, '-lc',
                                  'pacman-key --init && pacman-key --populate msys2 && ' \
                                  'pacman -Sy --noconfirm mingw-w64-ucrt-x86_64-libyaml']
                    }
                ),
                Action.new(
                    id: 'install_ruby_gems',
                    name: :run_command,
                    description: 'Install ruby gems with bundle install',
                    parameters: {
                        command: %w[bundle install]
                    }
                ),
                Action.new(
                    id: 'shared_git_config',
                    name: :link_file,
                    description: 'Apply shared Git configuration',
                    parameters: {
                        source: '.config/.gitconfig',
                        target: '~/.gitconfig'
                    },
                    elevation: :admin
                ),
                Action.new(
                    id: 'repository_git_hooks',
                    name: :run_command,
                    description: 'Configure repository Git hooks',
                    parameters: {
                        command: ['git', 'config', 'core.hooksPath', '.githooks']
                    }
                ),
                Action.new(
                    id: 'install_psscriptanalyzer',
                    name: :run_command,
                    description: 'Install PSScriptAnalyzer PowerShell module',
                    parameters: {
                        # The guard compares versions rather than checking presence: any
                        # already-installed version satisfies a presence check, which would
                        # skip the install and leave the pin unapplied.
                        command: ['pwsh', '-NoProfile', '-Command',
                                  'if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer | ' \
                                  "Where-Object { $_.Version -eq '#{PSSCRIPTANALYZER_VERSION}' })) " \
                                  '{ Install-Module PSScriptAnalyzer -RequiredVersion ' \
                                  "#{PSSCRIPTANALYZER_VERSION} -Scope CurrentUser -Force }"]
                    }
                ),
                Action.new(
                    id: 'mise_config',
                    name: :link_file,
                    description: 'Apply mise toolchain configuration',
                    parameters: {
                        source: '.config/mise/config.toml',
                        target: '~/.config/mise/config.toml'
                    },
                    elevation: :admin
                ),
                Action.new(
                    id: 'mise_install',
                    name: :run_command,
                    description: 'Install mise tools',
                    parameters: {
                        command: %w[mise install],
                        inputs: ['.config/mise/config.toml']
                    }
                ),
                Action.new(
                    id: 'windows_appx_bloat_removal',
                    name: :run_command,
                    description: 'Remove Windows AppX bloat',
                    platform: :windows,
                    parameters: {
                        command: [WINDOWS_POWERSHELL, '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
                                  '.\\scripts\\system\\Remove-AppxBloat.ps1'],
                        inputs: ['scripts/system/Remove-AppxBloat.ps1']
                    },
                    elevation: :admin
                ),
                Action.new(
                    id: 'windows_fastfetch_config',
                    name: :link_file,
                    description: 'Apply Windows Fastfetch configuration',
                    platform: :windows,
                    parameters: {
                        source: '.config/fastfetch-win.jsonc',
                        target: '%USERPROFILE%/.config/fastfetch/config.jsonc'
                    },
                    elevation: :admin
                ),
                Action.new(
                    id: 'windows_terminal_config',
                    name: :copy_file,
                    description: 'Apply Windows Terminal configuration',
                    platform: :windows,
                    parameters: {
                        source: '.config/windows-terminal.json',
                        target: WINDOWS_TERMINAL_TARGET
                    }
                ),
                Action.new(
                    id: 'powershell_profile',
                    name: :link_file,
                    description: 'Apply PowerShell profile',
                    platform: :windows,
                    parameters: {
                        source: 'scripts/shell/profile.ps1',
                        target: '%USERPROFILE%/Documents/PowerShell/Microsoft.PowerShell_profile.ps1'
                    },
                    elevation: :admin
                ),
                Action.new(
                    id: 'powershell_profile_extensions',
                    name: :link_file,
                    description: 'Apply PowerShell profile extensions',
                    platform: :windows,
                    parameters: {
                        source: 'scripts/shell/ProfileExtensions.ps1',
                        target: '%USERPROFILE%/Documents/PowerShell/ProfileExtensions.ps1'
                    },
                    elevation: :admin
                ),
                Action.new(
                    id: 'zed_settings',
                    name: :link_file,
                    description: 'Apply Zed settings',
                    platform: :windows,
                    parameters: {
                        source: '.config/zed/settings.json',
                        target: '%APPDATA%/Zed/settings.json'
                    },
                    elevation: :admin
                ),
                Action.new(
                    id: 'zed_evergarden_theme',
                    name: :link_file,
                    description: 'Apply Zed evergarden theme',
                    platform: :windows,
                    parameters: {
                        source: '.config/zed/themes/evergarden.json',
                        target: '%APPDATA%/Zed/themes/evergarden.json'
                    },
                    elevation: :admin
                )
            ]
        end

        # Loads private actions from private/actions.yml when available and applicable to the machine.
        #
        # @return [Array<Dotfiles::Action>]
        def private_actions
            manifest_path = File.join(@context.repository_root, PRIVATE_MANIFEST_PATH)
            return [] unless File.file?(manifest_path)

            data = YAML.safe_load_file(manifest_path)
            raw_actions = data.is_a?(Hash) ? data.fetch('actions', []) : []
            return [] unless raw_actions.is_a?(Array)

            raw_actions.filter_map do |entry|
                next unless entry.is_a?(Hash)
                next unless machine_matches?(entry['machine'])

                parameters = entry['parameters'].is_a?(Hash) ? entry['parameters'].transform_keys(&:to_sym) : {}

                Action.new(
                    id: entry.fetch('id'),
                    name: entry.fetch('name').to_sym,
                    description: entry.fetch('description'),
                    platform: entry.fetch('platform', 'shared').to_sym,
                    parameters: parameters,
                    elevation: entry.fetch('elevation', 'any').to_sym
                )
            end
        end

        def machine_matches?(machine_filter)
            return true if machine_filter.nil?

            targets = Array(machine_filter).map { |item| item.to_s.downcase }
            targets.include?(@context.hostname.to_s.downcase)
        end
    end
end
