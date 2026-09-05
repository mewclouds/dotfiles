# frozen_string_literal: true

require 'minitest/autorun'
require 'fileutils'
require 'json'
require 'rbconfig'
require 'stringio'
require 'tmpdir'
require_relative '../lib/dotfiles'

class DotfilesTest < Minitest::Test
    def test_status_reports_runtime_context
        output, error = capture_io do
            assert_equal 0, Dotfiles.run(['status'])
        end

        assert_empty error
        assert_includes output, 'Dotfiles orchestrator'
        assert_includes output, 'Platform:'
        assert_includes output, "Ruby: #{RUBY_VERSION}"
        assert_includes output, "Repository: #{Dotfiles.repository_root}"
    end

    def test_platform_includes_a_friendly_name_and_host_identifier
        assert_match(/\A(?:windows|linux|unknown) \(.+\)\z/, Dotfiles.platform)
    end

    def test_context_contains_runtime_information
        context = Dotfiles::Context.new(
            host_os: 'linux-gnu',
            ruby_version: '4.0.0',
            repository_root: '/tmp/dotfiles'
        )

        assert_equal 'linux', context.platform_name
        assert_equal 'linux (linux-gnu)', context.platform
        assert_equal '4.0.0', context.ruby_version
        assert_equal '/tmp/dotfiles', context.repository_root
    end

    def test_context_classifies_windows_hosts
        context = Dotfiles::Context.new(host_os: 'mingw32')

        assert_equal 'windows', context.platform_name
    end

    def test_context_contains_hostname
        context = Dotfiles::Context.new(hostname: 'synthetic-custom-host')

        assert_equal 'synthetic-custom-host', context.hostname
    end

    def test_context_defaults_to_system_hostname
        assert_equal Socket.gethostname, Dotfiles::Context.new.hostname
    end

    def test_desired_state_loads_private_actions_from_yaml_manifest
        Dir.mktmpdir do |repo_root|
            private_dir = File.join(repo_root, 'private')
            FileUtils.mkdir_p(private_dir)
            File.write(File.join(private_dir, 'actions.yml'), <<~YAML)
                actions:
                  - id: custom_private_link
                    name: link_file
                    description: Apply custom private link
                    platform: windows
                    parameters:
                      source: private/test.txt
                      target: ~/test.txt
            YAML

            context = Dotfiles::Context.new(repository_root: repo_root, host_os: 'mingw32')
            actions = Dotfiles::DesiredState.new(context).actions
            action = actions.find { |candidate| candidate.id == 'custom_private_link' }

            assert action
            assert_equal :link_file, action.name
            assert_equal 'Apply custom private link', action.description
            assert_equal :windows, action.platform
            assert_equal 'private/test.txt', action.parameters[:source]
            assert_equal '~/test.txt', action.parameters[:target]
        end
    end

    def test_desired_state_filters_private_actions_by_machine_hostname
        Dir.mktmpdir do |repo_root|
            private_dir = File.join(repo_root, 'private')
            FileUtils.mkdir_p(private_dir)
            File.write(File.join(private_dir, 'actions.yml'), <<~YAML)
                actions:
                  - id: host_a_only
                    name: run_command
                    description: Run on Host A only
                    machine: synthetic-host-a
                    parameters:
                      command: ["echo", "a"]
                  - id: host_b_only
                    name: run_command
                    description: Run on Host B only
                    machine: synthetic-host-b
                    parameters:
                      command: ["echo", "b"]
                  - id: all_hosts
                    name: run_command
                    description: Run on all hosts
                    parameters:
                      command: ["echo", "all"]
            YAML

            host_a_context = Dotfiles::Context.new(repository_root: repo_root, hostname: 'synthetic-host-a')
            host_a_actions = Dotfiles::DesiredState.new(host_a_context).actions.map(&:id)

            assert_includes host_a_actions, 'host_a_only'
            assert_includes host_a_actions, 'all_hosts'
            refute_includes host_a_actions, 'host_b_only'

            host_b_context = Dotfiles::Context.new(repository_root: repo_root, hostname: 'SYNTHETIC-HOST-B')
            host_b_actions = Dotfiles::DesiredState.new(host_b_context).actions.map(&:id)

            assert_includes host_b_actions, 'host_b_only'
            assert_includes host_b_actions, 'all_hosts'
            refute_includes host_b_actions, 'host_a_only'
        end
    end

    def test_desired_state_filters_private_actions_by_machine_array
        Dir.mktmpdir do |repo_root|
            private_dir = File.join(repo_root, 'private')
            FileUtils.mkdir_p(private_dir)
            File.write(File.join(private_dir, 'actions.yml'), <<~YAML)
                actions:
                  - id: cluster_action
                    name: run_command
                    description: Run on cluster hosts
                    machine:
                      - synthetic-host-a
                      - synthetic-host-b
                    parameters:
                      command: ["echo", "cluster"]
            YAML

            matching_context = Dotfiles::Context.new(repository_root: repo_root, hostname: 'synthetic-host-b')
            matching_actions = Dotfiles::DesiredState.new(matching_context).actions.map(&:id)
            assert_includes matching_actions, 'cluster_action'

            non_matching_context = Dotfiles::Context.new(repository_root: repo_root, hostname: 'synthetic-host-c')
            non_matching_actions = Dotfiles::DesiredState.new(non_matching_context).actions.map(&:id)
            refute_includes non_matching_actions, 'cluster_action'
        end
    end

    def test_desired_state_handles_missing_or_empty_private_manifest_gracefully
        Dir.mktmpdir do |repo_root|
            context = Dotfiles::Context.new(repository_root: repo_root)
            actions = Dotfiles::DesiredState.new(context).actions

            refute_empty actions
            refute(actions.any? { |action| action.id.start_with?('private_') })

            private_dir = File.join(repo_root, 'private')
            FileUtils.mkdir_p(private_dir)
            File.write(File.join(private_dir, 'actions.yml'), '')

            actions = Dotfiles::DesiredState.new(context).actions
            refute_empty actions
        end
    end

    def test_plan_contains_shared_configuration_actions
        context = Dotfiles::Context.new(host_os: 'mingw32')
        plan = Dotfiles::Plan.new(Dotfiles::DesiredState.new(context).actions)
                             .for_platform(context.platform_name)
        actions_by_id = plan.actions.to_h { |action| [action.id, action] }

        install_ruby_gems = actions_by_id.fetch('install_ruby_gems')
        assert_equal :run_command, install_ruby_gems.name
        assert_equal 'Install ruby gems with bundle install', install_ruby_gems.description
        assert_equal %w[bundle install], install_ruby_gems.parameters[:command]

        git_config = actions_by_id.fetch('shared_git_config')
        assert_equal :link_file, git_config.name
        assert_equal '.config/.gitconfig', git_config.parameters[:source]
        assert_equal '~/.gitconfig', git_config.parameters[:target]

        git_hooks = actions_by_id.fetch('repository_git_hooks')
        assert_equal :run_command, git_hooks.name
        assert_equal ['git', 'config', 'core.hooksPath', '.githooks'], git_hooks.parameters[:command]

        mise_config = actions_by_id.fetch('mise_config')
        assert_equal :link_file, mise_config.name
        assert_equal '.config/mise/config.toml', mise_config.parameters[:source]
        assert_equal '~/.config/mise/config.toml', mise_config.parameters[:target]

        fastfetch_config = actions_by_id.fetch('windows_fastfetch_config')
        assert_equal :link_file, fastfetch_config.name
        assert_equal :windows, fastfetch_config.platform
        assert_equal '.config/fastfetch-win.jsonc', fastfetch_config.parameters[:source]
        assert_equal '%USERPROFILE%/.config/fastfetch/config.jsonc', fastfetch_config.parameters[:target]

        terminal_config = actions_by_id.fetch('windows_terminal_config')
        assert_equal :copy_file, terminal_config.name
        assert_equal :windows, terminal_config.platform
        assert_equal '.config/windows-terminal.json', terminal_config.parameters[:source]
        assert_equal '%LOCALAPPDATA%/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json',
                     terminal_config.parameters[:target]

        profile = actions_by_id.fetch('powershell_profile')
        assert_equal :link_file, profile.name
        assert_equal 'scripts/shell/profile.ps1', profile.parameters[:source]
        assert_equal '%USERPROFILE%/Documents/PowerShell/Microsoft.PowerShell_profile.ps1',
                     profile.parameters[:target]

        profile_extensions = actions_by_id.fetch('powershell_profile_extensions')
        assert_equal :link_file, profile_extensions.name
        assert_equal 'scripts/shell/ProfileExtensions.ps1', profile_extensions.parameters[:source]
        assert_equal '%USERPROFILE%/Documents/PowerShell/ProfileExtensions.ps1',
                     profile_extensions.parameters[:target]

        zed_settings = actions_by_id.fetch('zed_settings')
        assert_equal :link_file, zed_settings.name
        assert_equal :windows, zed_settings.platform
        assert_equal '.config/zed/settings.json', zed_settings.parameters[:source]
        assert_equal '%APPDATA%/Zed/settings.json', zed_settings.parameters[:target]

        zed_theme = actions_by_id.fetch('zed_evergarden_theme')
        assert_equal :link_file, zed_theme.name
        assert_equal :windows, zed_theme.platform
        assert_equal '.config/zed/themes/evergarden.json', zed_theme.parameters[:source]
        assert_equal '%APPDATA%/Zed/themes/evergarden.json', zed_theme.parameters[:target]
    end

    def test_plan_contains_the_install_ruby_gems_command
        action = Dotfiles::DesiredState.new(Dotfiles::Context.new).actions
                                       .find { |candidate| candidate.id == 'install_ruby_gems' }

        assert_equal :run_command, action.name
        assert_equal 'Install ruby gems with bundle install', action.description
        assert_equal %w[bundle install], action.parameters[:command]
    end

    def test_plan_contains_the_repository_git_hooks_command
        action = Dotfiles::DesiredState.new(Dotfiles::Context.new).actions
                                       .find { |candidate| candidate.id == 'repository_git_hooks' }

        assert_equal :run_command, action.name
        assert_equal 'Configure repository Git hooks', action.description
        assert_equal ['git', 'config', 'core.hooksPath', '.githooks'], action.parameters[:command]
    end

    def test_plan_contains_the_mise_install_command
        action = Dotfiles::DesiredState.new(Dotfiles::Context.new).actions
                                       .find { |candidate| candidate.id == 'mise_install' }

        assert_equal :run_command, action.name
        assert_equal 'Install mise tools', action.description
        assert_equal %w[mise install], action.parameters[:command]
    end

    def test_plan_contains_the_windows_appx_bloat_removal_command
        context = Dotfiles::Context.new(host_os: 'mingw32')
        action = Dotfiles::DesiredState.new(context).actions
                                       .find { |candidate| candidate.id == 'windows_appx_bloat_removal' }

        assert_equal :windows, action.platform
        assert_equal :run_command, action.name
        assert_equal 'Remove Windows AppX bloat', action.description
        expected_command = [
            'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe',
            '-NoProfile',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            '.\\scripts\\system\\Remove-AppxBloat.ps1'
        ]
        assert_equal expected_command, action.parameters[:command]
        assert_equal ['scripts/system/Remove-AppxBloat.ps1'], action.parameters[:inputs]
    end

    def test_plan_command_reports_shared_configuration
        output, error = capture_io do
            assert_equal 0, Dotfiles.run(['plan'])
        end

        assert_empty error
        assert_includes output, 'Execution plan'
        assert_includes output, 'Install ruby gems with bundle install'
        assert_includes output, 'Apply shared Git configuration'
        assert_includes output, 'Configure repository Git hooks'
        assert_includes output, 'Apply mise toolchain configuration'
        assert_includes output, 'Prepare SSH signing key after apply'
        assert_includes output, 'not run automatically'
    end

    def test_signing_setup_confirmation_defaults_to_no
        output = StringIO.new

        refute Dotfiles.signing_setup_requested?(input: StringIO.new("\n"), output: output)
        assert_equal 'Prepare SSH signing key now? [y/N] ', output.string
    end

    def test_signing_setup_confirmation_accepts_yes
        assert Dotfiles.signing_setup_requested?(input: StringIO.new("yes\n"), output: StringIO.new)
    end

    def test_plan_holds_descriptive_actions
        action = Dotfiles::Action.new(
            name: :install_ruby,
            description: 'Install Ruby',
            platform: :windows,
            parameters: {
                source: 'install/ruby.ps1',
                target: '~/ruby.ps1'
            }
        )
        plan = Dotfiles::Plan.new.add(action)

        assert_equal 1, plan.size
        assert_equal action, plan.actions.first
        assert_equal :install_ruby, plan.actions.first.name
        assert_equal 'Install Ruby', plan.actions.first.description
        assert_equal :windows, plan.actions.first.platform
        assert_equal 'install/ruby.ps1', plan.actions.first.parameters[:source]
        assert_equal '~/ruby.ps1', plan.actions.first.parameters[:target]
    end

    def test_plan_actions_cannot_be_modified_through_reader
        plan = Dotfiles::Plan.new

        assert_raises(FrozenError) do
            plan.actions << Dotfiles::Action.new(name: :test, description: 'Test')
        end

        assert_empty plan.actions
    end

    def test_plan_rejects_duplicate_action_ids
        first = Dotfiles::Action.new(id: 'duplicate', name: :first, description: 'First')
        second = Dotfiles::Action.new(id: 'duplicate', name: :second, description: 'Second')

        error = assert_raises(RuntimeError) do
            Dotfiles::Plan.new([first, second])
        end

        assert_equal 'Duplicate action ID: duplicate', error.message
    end

    def test_plan_filters_platform_specific_actions
        shared = Dotfiles::Action.new(name: :shared, description: 'Shared')
        windows = Dotfiles::Action.new(name: :windows, description: 'Windows', platform: :windows)
        linux = Dotfiles::Action.new(name: :linux, description: 'Linux', platform: :linux)
        plan = Dotfiles::Plan.new([shared, windows, linux])

        assert_equal [shared, windows], plan.for_platform(:windows).actions
        assert_equal [shared, linux], plan.for_platform(:linux).actions
    end

    def test_linux_plan_filters_actions_by_platform
        Dir.mktmpdir do |repo_root|
            context = Dotfiles::Context.new(repository_root: repo_root, host_os: 'linux-gnu')
            plan = Dotfiles::Plan.new(Dotfiles::DesiredState.new(context).actions)
                                 .for_platform(context.platform_name)
            action_ids = plan.actions.map(&:id)

            shared_ids = %w[install_ruby_gems shared_git_config repository_git_hooks mise_config mise_install]
            shared_ids.each { |id| assert_includes action_ids, id }

            windows_only_ids = %w[
                ruby_devkit_libyaml windows_appx_bloat_removal windows_fastfetch_config windows_terminal_config
                powershell_profile powershell_profile_extensions zed_settings zed_evergarden_theme
            ]
            windows_only_ids.each { |id| refute_includes action_ids, id }
        end
    end

    def test_executor_links_a_file_without_overwriting
        Dir.mktmpdir do |directory|
            source_directory = File.join(directory, 'repository')
            home_directory = File.join(directory, 'home')
            FileUtils.mkdir_p(source_directory)
            File.write(File.join(source_directory, 'config'), "value\n")

            action = Dotfiles::Action.new(
                name: :link_file,
                description: 'Link test file',
                parameters: { source: 'config', target: '~/config' }
            )

            begin
                result = Dotfiles::Executor.new(
                    repository_root: source_directory,
                    home_directory: home_directory
                ).execute(Dotfiles::Plan.new([action]))
            rescue SystemCallError => e
                skip "Symlinks are unavailable: #{e.message}"
            end

            assert_equal [:linked], result
            target = File.join(home_directory, 'config')
            assert File.symlink?(target)
            assert_equal File.realpath(File.join(source_directory, 'config')), File.realpath(target)
        end
    end

    def test_executor_refuses_to_replace_a_regular_file
        Dir.mktmpdir do |directory|
            source_directory = File.join(directory, 'repository')
            home_directory = File.join(directory, 'home')
            FileUtils.mkdir_p(source_directory)
            FileUtils.mkdir_p(home_directory)
            File.write(File.join(source_directory, 'config'), "new\n")
            File.write(File.join(home_directory, 'config'), "old\n")

            action = Dotfiles::Action.new(
                name: :link_file,
                description: 'Link test file',
                parameters: { source: 'config', target: '~/config' }
            )

            executor = Dotfiles::Executor.new(
                repository_root: source_directory,
                home_directory: home_directory
            )

            error = assert_raises(RuntimeError) do
                executor.execute(Dotfiles::Plan.new([action]))
            end
            assert_match(/Refusing to replace/, error.message)
            assert_equal "old\n", File.read(File.join(home_directory, 'config'))
        end
    end

    def test_executor_reports_pending_link
        Dir.mktmpdir do |directory|
            source_directory = File.join(directory, 'repository')
            home_directory = File.join(directory, 'home')
            FileUtils.mkdir_p(source_directory)
            File.write(File.join(source_directory, 'config'), "value\n")

            action = Dotfiles::Action.new(
                name: :link_file,
                description: 'Link test file',
                parameters: { source: 'config', target: '~/config' }
            )

            executor = Dotfiles::Executor.new(
                repository_root: source_directory,
                home_directory: home_directory
            )

            assert_equal :pending, executor.status(action)
        end
    end

    def test_executor_force_copies_a_file_over_an_existing_file
        Dir.mktmpdir do |directory|
            source_directory = File.join(directory, 'repository')
            home_directory = File.join(directory, 'home')
            FileUtils.mkdir_p(source_directory)
            FileUtils.mkdir_p(home_directory)
            File.write(File.join(source_directory, 'settings.json'), "desired\n")
            File.write(File.join(home_directory, 'settings.json'), "default\n")

            action = Dotfiles::Action.new(
                name: :copy_file,
                description: 'Copy test file',
                parameters: { source: 'settings.json', target: '~/settings.json' }
            )

            result = Dotfiles::Executor.new(
                repository_root: source_directory,
                home_directory: home_directory
            ).execute(Dotfiles::Plan.new([action]))

            assert_equal [:copied], result
            assert_equal "desired\n", File.read(File.join(home_directory, 'settings.json'))
        end
    end

    def test_executor_skips_copying_an_unchanged_file
        Dir.mktmpdir do |directory|
            source_directory = File.join(directory, 'repository')
            home_directory = File.join(directory, 'home')
            FileUtils.mkdir_p(source_directory)
            FileUtils.mkdir_p(home_directory)
            File.write(File.join(source_directory, 'settings.json'), "desired\n")
            File.write(File.join(home_directory, 'settings.json'), "desired\n")

            action = Dotfiles::Action.new(
                name: :copy_file,
                description: 'Copy test file',
                parameters: { source: 'settings.json', target: '~/settings.json' }
            )

            result = Dotfiles::Executor.new(
                repository_root: source_directory,
                home_directory: home_directory
            ).execute(Dotfiles::Plan.new([action]))

            assert_equal [:already_copied], result
        end
    end

    def test_executor_runs_a_command_action
        Dir.mktmpdir do |repository_root|
            action = Dotfiles::Action.new(
                id: 'test_command',
                name: :run_command,
                description: 'Run test command',
                parameters: { command: [RbConfig.ruby, '-e', 'exit 0'] }
            )

            result = Dotfiles::Executor.new(repository_root: repository_root).execute(Dotfiles::Plan.new([action]))

            assert_equal [:executed], result
        end
    end

    def test_executor_reports_a_failed_command
        Dir.mktmpdir do |repository_root|
            action = Dotfiles::Action.new(
                id: 'failing_test_command',
                name: :run_command,
                description: 'Run failing test command',
                parameters: { command: [RbConfig.ruby, '-e', 'exit 1'] }
            )

            error = assert_raises(RuntimeError) do
                Dotfiles::Executor.new(repository_root: repository_root).execute(Dotfiles::Plan.new([action]))
            end

            assert_match(/Command failed with exit code 1/, error.message)
        end
    end

    def test_executor_skips_a_command_with_a_matching_fingerprint
        Dir.mktmpdir do |repository_root|
            marker = File.join(repository_root, 'runs')
            File.write(marker, '0')
            action = Dotfiles::Action.new(
                id: 'count_command',
                name: :run_command,
                description: 'Count command runs',
                parameters: {
                    command: [
                        RbConfig.ruby,
                        '-e',
                        'path = ARGV.fetch(0); File.write(path, (File.read(path).to_i + 1).to_s)',
                        marker
                    ]
                }
            )
            executor = Dotfiles::Executor.new(repository_root: repository_root)

            assert_equal [:executed], executor.execute(Dotfiles::Plan.new([action]))
            reloaded_executor = Dotfiles::Executor.new(repository_root: repository_root)
            assert_equal [:already_applied], reloaded_executor.execute(Dotfiles::Plan.new([action]))
            assert_equal '1', File.read(marker)
            state = JSON.parse(File.read(File.join(repository_root, '.local', 'state.json')))
            assert_equal 'completed', state.dig('actions', 'count_command', 'status')
        end
    end

    def test_executor_reruns_a_command_when_an_input_changes
        Dir.mktmpdir do |repository_root|
            input_path = File.join(repository_root, 'input.txt')
            counter_path = File.join(repository_root, 'runs')
            File.write(input_path, "first\n")
            File.write(counter_path, '0')
            action = Dotfiles::Action.new(
                id: 'input_sensitive_command',
                name: :run_command,
                description: 'Run input-sensitive command',
                parameters: {
                    command: [
                        RbConfig.ruby,
                        '-e',
                        'path = ARGV.fetch(0); File.write(path, (File.read(path).to_i + 1).to_s)',
                        counter_path
                    ],
                    inputs: ['input.txt']
                }
            )
            executor = Dotfiles::Executor.new(repository_root: repository_root)

            assert_equal [:executed], executor.execute(Dotfiles::Plan.new([action]))
            File.write(input_path, "second\n")

            assert_equal [:executed], executor.execute(Dotfiles::Plan.new([action]))
            assert_equal '2', File.read(counter_path)
        end
    end

    def test_executor_rejects_a_malformed_state_entry
        Dir.mktmpdir do |repository_root|
            state_directory = File.join(repository_root, '.local')
            FileUtils.mkdir_p(state_directory)
            File.write(
                File.join(state_directory, 'state.json'),
                JSON.generate('version' => 1, 'actions' => { 'broken' => { 'status' => 'completed' } })
            )

            error = assert_raises(RuntimeError) do
                Dotfiles::Executor.new(repository_root: repository_root)
            end

            assert_equal 'Invalid orchestration state entry: broken', error.message
        end
    end

    def test_executor_runs_commands_from_the_repository_root
        Dir.mktmpdir do |repository_root|
            action = Dotfiles::Action.new(
                name: :run_command,
                description: 'Check command directory',
                parameters: {
                    command: [
                        RbConfig.ruby,
                        '-e',
                        'exit(File.expand_path(Dir.pwd) == File.expand_path(ARGV.fetch(0)) ? 0 : 1)',
                        repository_root
                    ]
                }
            )

            result = Dotfiles::Executor.new(repository_root: repository_root).execute(Dotfiles::Plan.new([action]))

            assert_equal [:executed], result
        end
    end

    def test_executor_rejects_an_invalid_command
        action = Dotfiles::Action.new(
            name: :run_command,
            description: 'Run invalid command',
            parameters: { command: "ruby -e 'exit 0'" }
        )

        error = assert_raises(ArgumentError) do
            Dotfiles::Executor.new(repository_root: Dir.pwd).execute(Dotfiles::Plan.new([action]))
        end

        assert_equal 'Command must be a non-empty array of strings.', error.message
    end

    def test_executor_force_copies_a_file_over_an_existing_symlink
        Dir.mktmpdir do |directory|
            source_directory = File.join(directory, 'repository')
            home_directory = File.join(directory, 'home')
            other_directory = File.join(directory, 'other')
            FileUtils.mkdir_p(source_directory)
            FileUtils.mkdir_p(home_directory)
            FileUtils.mkdir_p(other_directory)
            File.write(File.join(source_directory, 'settings.json'), "desired\n")
            File.write(File.join(other_directory, 'settings.json'), "linked\n")

            target = File.join(home_directory, 'settings.json')
            begin
                File.symlink(File.join(other_directory, 'settings.json'), target)
            rescue SystemCallError => e
                skip "Symlinks are unavailable: #{e.message}"
            end

            action = Dotfiles::Action.new(
                name: :copy_file,
                description: 'Copy test file',
                parameters: { source: 'settings.json', target: '~/settings.json' }
            )

            result = Dotfiles::Executor.new(
                repository_root: source_directory,
                home_directory: home_directory
            ).execute(Dotfiles::Plan.new([action]))

            assert_equal [:copied], result
            refute File.symlink?(target)
            assert_equal "desired\n", File.read(target)
        end
    end

    def test_executor_reports_blocked_link
        Dir.mktmpdir do |directory|
            source_directory = File.join(directory, 'repository')
            home_directory = File.join(directory, 'home')
            FileUtils.mkdir_p(source_directory)
            FileUtils.mkdir_p(home_directory)
            File.write(File.join(source_directory, 'config'), "new\n")
            File.write(File.join(home_directory, 'config'), "old\n")

            action = Dotfiles::Action.new(
                name: :link_file,
                description: 'Link test file',
                parameters: { source: 'config', target: '~/config' }
            )

            executor = Dotfiles::Executor.new(
                repository_root: source_directory,
                home_directory: home_directory
            )

            assert_equal :blocked, executor.status(action)
        end
    end

    def test_executor_clean_mode_replaces_a_regular_file_with_a_symlink
        Dir.mktmpdir do |directory|
            source_directory = File.join(directory, 'repository')
            home_directory = File.join(directory, 'home')
            FileUtils.mkdir_p(source_directory)
            FileUtils.mkdir_p(home_directory)
            File.write(File.join(source_directory, 'config'), "new\n")
            File.write(File.join(home_directory, 'config'), "old\n")

            action = Dotfiles::Action.new(
                name: :link_file,
                description: 'Link test file',
                parameters: { source: 'config', target: '~/config' }
            )

            begin
                result = Dotfiles::Executor.new(
                    repository_root: source_directory,
                    home_directory: home_directory,
                    clean: true
                ).execute(Dotfiles::Plan.new([action]))
            rescue SystemCallError => e
                skip "Symlinks are unavailable: #{e.message}"
            end

            assert_equal [:linked], result
            target = File.join(home_directory, 'config')
            assert File.symlink?(target)
            assert_equal "new\n", File.read(target)
        end
    end

    def test_clean_option_accepts_both_cli_spellings
        assert Dotfiles.clean_option(['--clean'])
        assert Dotfiles.clean_option(['-Clean'])
        refute Dotfiles.clean_option([])
    end

    def test_signing_setup_generates_and_uploads_a_new_key
        Dir.mktmpdir do |directory|
            runner = FakeCommandRunner.new
            context = Dotfiles::Context.new(host_os: 'mingw32')
            input = StringIO.new("y\nWindows Desktop\n")

            Dotfiles::SigningSetup.new(
                context,
                input: input,
                output: StringIO.new,
                home_directory: directory,
                runner: runner
            ).run

            assert_includes runner.commands, ['gh', 'ssh-key', 'add',
                                              File.join(directory, '.ssh', 'id_ed25519_signing.pub'),
                                              '--type', 'signing', '--title', 'Windows Desktop']
        end
    end

    def test_signing_setup_does_not_reupload_an_existing_key
        Dir.mktmpdir do |directory|
            key_path = File.join(directory, '.ssh', 'id_ed25519_signing')
            public_key = 'ssh-ed25519 AAAAexisting local-comment'
            FileUtils.mkdir_p(File.dirname(key_path))
            File.write(key_path, 'private')
            File.write("#{key_path}.pub", "#{public_key}\n")

            runner = FakeCommandRunner.new(github_key: 'ssh-ed25519 AAAAexisting github-comment')
            Dotfiles::SigningSetup.new(
                Dotfiles::Context.new(host_os: 'mingw32'),
                input: StringIO.new,
                output: StringIO.new,
                home_directory: directory,
                runner: runner
            ).run

            assert_includes runner.commands,
                            ['gh', 'auth', 'refresh', '-h', 'github.com', '-s', 'admin:ssh_signing_key']
            refute(runner.commands.any? { |command| command.first(3) == %w[gh ssh-key add] })
        end
    end

    def test_signing_setup_reports_a_missing_signing_key_scope
        Dir.mktmpdir do |directory|
            key_path = File.join(directory, '.ssh', 'id_ed25519_signing')
            FileUtils.mkdir_p(File.dirname(key_path))
            File.write(key_path, 'private')
            File.write("#{key_path}.pub", "ssh-ed25519 AAAAexisting local-comment\n")

            runner = FakeCommandRunner.new(auth_refresh_failure: true)
            error = assert_raises(RuntimeError) do
                Dotfiles::SigningSetup.new(
                    Dotfiles::Context.new(host_os: 'mingw32'),
                    input: StringIO.new,
                    output: StringIO.new,
                    home_directory: directory,
                    runner: runner
                ).run
            end

            assert_match(/could not obtain the SSH signing-key permission/, error.message)
            refute runner.commands.include?(['gh', 'api', 'user/ssh_signing_keys'])
        end
    end

    def test_signing_setup_rejects_an_invalid_github_key_response
        Dir.mktmpdir do |directory|
            key_path = File.join(directory, '.ssh', 'id_ed25519_signing')
            FileUtils.mkdir_p(File.dirname(key_path))
            File.write(key_path, 'private')
            File.write("#{key_path}.pub", "ssh-ed25519 AAAAexisting local-comment\n")

            runner = FakeCommandRunner.new(github_response: '{}')
            error = assert_raises(RuntimeError) do
                Dotfiles::SigningSetup.new(
                    Dotfiles::Context.new(host_os: 'mingw32'),
                    input: StringIO.new,
                    output: StringIO.new,
                    home_directory: directory,
                    runner: runner
                ).run
            end

            assert_match(/unexpected SSH signing-key response/, error.message)
        end
    end

    def test_action_parameters_cannot_be_modified_through_reader
        action = Dotfiles::Action.new(
            name: :install_tool,
            description: 'Install a tool',
            parameters: { tool: 'ruby' }
        )

        assert_raises(FrozenError) do
            action.parameters[:tool] = 'python'
        end

        assert_equal 'ruby', action.parameters[:tool]
    end

    def test_repository_root_is_based_on_the_library_location
        expected_root = File.expand_path('..', __dir__)

        assert_equal expected_root, Dotfiles.repository_root
    end

    def test_run_defaults_to_help
        output, = capture_io do
            assert_equal 0, Dotfiles.run
        end

        assert_includes output, 'Usage: dotfiles'
    end

    def test_help_command_lists_every_command
        output, error = capture_io do
            assert_equal 0, Dotfiles.run(['help'])
        end

        assert_empty error
        assert_includes output, 'Usage: dotfiles'
        assert_match(/^\s+status\s/, output)
        assert_match(/^\s+plan\s/, output)
        assert_match(/^\s+apply \[--clean\]\s/, output)
        assert_match(/^\s+decrypt\s/, output)
        assert_match(/^\s+help\s/, output)
    end

    def test_help_flags_alias_the_help_command
        ['-h', '--help'].each do |flag|
            output, = capture_io do
                assert_equal 0, Dotfiles.run([flag])
            end

            assert_includes output, 'Usage: dotfiles'
        end
    end

    def test_unknown_commands_raise_an_error
        error = assert_raises(RuntimeError) do
            Dotfiles.run(['unknown'])
        end

        assert_equal 'Unknown command: unknown', error.message
    end

    def test_private_state_skips_when_private_directory_already_exists_and_is_non_empty
        Dir.mktmpdir do |repo_root|
            private_dir = File.join(repo_root, 'private')
            FileUtils.mkdir_p(private_dir)
            File.write(File.join(private_dir, 'setup.ps1'), "existing\n")
            File.write(File.join(repo_root, 'private.age'), 'encrypted')

            runner = FakeCommandRunner.new
            output = StringIO.new

            result = Dotfiles::PrivateState.new(
                repository_root: repo_root,
                output: output,
                runner: runner
            ).decrypt

            assert_equal :already_present, result
            assert_includes output.string, 'Private state already present; skipping decryption.'
            assert_empty runner.commands
            assert_equal "existing\n", File.read(File.join(private_dir, 'setup.ps1'))
        end
    end

    def test_private_state_returns_missing_archive_when_archive_is_absent
        Dir.mktmpdir do |repo_root|
            runner = FakeCommandRunner.new
            output = StringIO.new

            result = Dotfiles::PrivateState.new(
                repository_root: repo_root,
                output: output,
                runner: runner
            ).decrypt

            assert_equal :missing_archive, result
            assert_empty runner.commands
        end
    end

    def test_private_state_decrypts_and_extracts_when_not_present
        Dir.mktmpdir do |repo_root|
            archive_path = File.join(repo_root, 'private.age')
            File.write(archive_path, 'encrypted_bytes')
            runner = FakeCommandRunner.new
            output = StringIO.new

            result = Dotfiles::PrivateState.new(
                repository_root: repo_root,
                output: output,
                runner: runner
            ).decrypt

            assert_equal :decrypted, result
            assert_includes output.string, 'Private state decrypted successfully.'
            assert(runner.commands.any? { |cmd| cmd.first(3) == %w[bw get notes] })
            assert(runner.commands.any? { |cmd| cmd.first == 'age' })
            assert(runner.commands.any? { |cmd| cmd.first == 'tar' })
            assert File.file?(File.join(repo_root, 'private', 'setup.ps1'))
        end
    end

    def test_private_state_reports_bitwarden_retrieval_failure
        Dir.mktmpdir do |repo_root|
            archive_path = File.join(repo_root, 'private.age')
            File.write(archive_path, 'encrypted_bytes')
            runner = FakeCommandRunner.new(bw_failure: true)

            error = assert_raises(RuntimeError) do
                Dotfiles::PrivateState.new(
                    repository_root: repo_root,
                    output: StringIO.new,
                    runner: runner
                ).decrypt
            end

            assert_match(/Bitwarden CLI failed to retrieve/, error.message)
        end
    end

    def test_private_state_prompts_and_unlocks_when_vault_is_locked
        Dir.mktmpdir do |repo_root|
            archive_path = File.join(repo_root, 'private.age')
            File.write(archive_path, 'encrypted_bytes')
            runner = FakeCommandRunner.new(bw_status: 'locked')
            input = StringIO.new("master_pass123\n")
            output = StringIO.new

            result = Dotfiles::PrivateState.new(
                repository_root: repo_root,
                input: input,
                output: output,
                runner: runner
            ).decrypt

            assert_equal :decrypted, result
            assert(runner.commands.any? { |cmd| cmd.first(2) == %w[bw unlock] })
            assert(runner.commands.any? { |cmd| cmd.first(3) == %w[bw get notes] })
            assert File.file?(File.join(repo_root, 'private', 'setup.ps1'))
        end
    end

    def test_private_state_handles_unauthenticated_bitwarden_flow
        Dir.mktmpdir do |repo_root|
            archive_path = File.join(repo_root, 'private.age')
            File.write(archive_path, 'encrypted_bytes')
            runner = FakeCommandRunner.new(bw_status: 'unauthenticated')
            input = StringIO.new("master_pass123\n")
            output = StringIO.new

            result = Dotfiles::PrivateState.new(
                repository_root: repo_root,
                input: input,
                output: output,
                runner: runner
            ).decrypt

            assert_equal :decrypted, result
            assert(runner.commands.any? { |cmd| cmd.first(2) == %w[bw login] })
            assert(runner.commands.any? { |cmd| cmd.first(2) == %w[bw unlock] })
            assert(runner.commands.any? { |cmd| cmd.first(3) == %w[bw get notes] })
            assert File.file?(File.join(repo_root, 'private', 'setup.ps1'))
        end
    end

    def test_private_state_rejects_empty_master_password
        Dir.mktmpdir do |repo_root|
            archive_path = File.join(repo_root, 'private.age')
            File.write(archive_path, 'encrypted_bytes')
            runner = FakeCommandRunner.new(bw_status: 'locked')
            input = StringIO.new("\n")

            error = assert_raises(RuntimeError) do
                Dotfiles::PrivateState.new(
                    repository_root: repo_root,
                    input: input,
                    output: StringIO.new,
                    runner: runner
                ).decrypt
            end

            assert_equal 'Master password cannot be empty.', error.message
        end
    end

    def test_private_state_reports_age_decryption_failure
        Dir.mktmpdir do |repo_root|
            archive_path = File.join(repo_root, 'private.age')
            File.write(archive_path, 'encrypted_bytes')
            runner = FakeCommandRunner.new(age_failure: true)

            error = assert_raises(RuntimeError) do
                Dotfiles::PrivateState.new(
                    repository_root: repo_root,
                    output: StringIO.new,
                    runner: runner
                ).decrypt
            end

            assert_match(/Failed to decrypt private state archive/, error.message)
        end
    end

    def test_private_state_extracts_root_relative_archive
        Dir.mktmpdir do |repo_root|
            archive_path = File.join(repo_root, 'private.age')
            File.write(archive_path, 'encrypted_bytes')
            runner = FakeCommandRunner.new(root_relative_tar: true)

            result = Dotfiles::PrivateState.new(
                repository_root: repo_root,
                output: StringIO.new,
                runner: runner
            ).decrypt

            assert_equal :decrypted, result
            assert File.file?(File.join(repo_root, 'private', 'setup.ps1'))
        end
    end

    def test_decrypt_command_dispatches_successfully
        Dir.mktmpdir do |repo_root|
            runner = FakeCommandRunner.new
            output = StringIO.new
            private_state = Dotfiles::PrivateState.new(repository_root: repo_root, output: output, runner: runner)

            assert_equal 0, Dotfiles.run(['decrypt'], private_state: private_state)
        end
    end

    def test_unlock_command_alias_dispatches_successfully
        Dir.mktmpdir do |repo_root|
            runner = FakeCommandRunner.new
            output = StringIO.new
            private_state = Dotfiles::PrivateState.new(repository_root: repo_root, output: output, runner: runner)

            assert_equal 0, Dotfiles.run(['unlock'], private_state: private_state)
        end
    end

    def test_command_runner_captures_successful_output
        runner = Dotfiles::CommandRunner.new
        output = runner.capture([RbConfig.ruby, '-e', "puts 'runner test'"])

        assert_equal "runner test\n", output
    end

    def test_command_runner_capture_raises_failure_on_error
        runner = Dotfiles::CommandRunner.new
        error = assert_raises(Dotfiles::CommandRunner::Failure) do
            runner.capture([RbConfig.ruby, '-e', "warn 'capture failure'; exit 1"])
        end

        assert_includes error.message, 'capture failure'
    end

    def test_command_runner_capture_provides_fallback_message_when_streams_are_empty
        runner = Dotfiles::CommandRunner.new
        error = assert_raises(Dotfiles::CommandRunner::Failure) do
            runner.capture([RbConfig.ruby, '-e', 'exit 1'])
        end

        assert_includes error.message, 'command failed (1)'
    end

    def test_command_runner_interactive_executes_successfully
        runner = Dotfiles::CommandRunner.new
        assert_silent do
            runner.interactive([RbConfig.ruby, '-e', 'exit 0'])
        end
    end

    def test_command_runner_interactive_raises_failure_on_error
        runner = Dotfiles::CommandRunner.new
        error = assert_raises(Dotfiles::CommandRunner::Failure) do
            runner.interactive([RbConfig.ruby, '-e', 'exit 1'])
        end

        assert_includes error.message, 'command failed'
    end

    class FakeCommandRunner
        attr_reader :commands

        def initialize(github_key: nil, github_response: nil,
                       auth_refresh_failure: false, bw_failure: false, bw_identity: nil, bw_status: 'unlocked',
                       age_failure: false, root_relative_tar: false)
            @github_key = github_key
            @github_response = github_response
            @auth_refresh_failure = auth_refresh_failure
            @bw_failure = bw_failure
            @bw_identity = bw_identity
            @bw_status = bw_status
            @age_failure = age_failure
            @root_relative_tar = root_relative_tar
            @commands = []
        end

        def capture(command)
            @commands << command
            return '' if command == %w[gh auth status]
            return @github_response if command == ['gh', 'api', 'user/ssh_signing_keys'] && @github_response
            return [{ 'key' => @github_key }].to_json if command == ['gh', 'api',
                                                                     'user/ssh_signing_keys'] && @github_key
            return '[]' if command == ['gh', 'api', 'user/ssh_signing_keys']

            return { 'status' => @bw_status }.to_json if command == %w[bw status]
            return 'session_key_123' if command.first(2) == %w[bw unlock]

            if command.first(3) == %w[bw get notes]
                raise Dotfiles::CommandRunner::Failure, 'vault is locked' if @bw_failure

                return @bw_identity || 'AGE-SECRET-KEY-1TEST...'
            end
            if command.first == 'age'
                raise Dotfiles::CommandRunner::Failure, 'decryption failed' if @age_failure

                output_file = command[command.index('-o') + 1]
                File.write(output_file, 'fake_zip_content')
                return ''
            end
            if command.first == 'tar'
                dest_dir = command[command.index('-C') + 1]
                if @root_relative_tar
                    File.write(File.join(dest_dir, 'setup.ps1'), '# root relative private setup')
                else
                    private_dir = File.join(dest_dir, 'private')
                    FileUtils.mkdir_p(private_dir)
                    File.write(File.join(private_dir, 'setup.ps1'), '# private setup')
                end
                return ''
            end

            ''
        end

        def interactive(command)
            @commands << command
            if command.first(2) == %w[bw login]
                @bw_status = 'locked'
                return true
            end

            if command.first(3) == %w[gh auth refresh] && @auth_refresh_failure
                raise Dotfiles::CommandRunner::Failure, 'required scope was not granted'
            end

            return unless command.first == 'ssh-keygen'

            key_path = command.last
            FileUtils.mkdir_p(File.dirname(key_path))
            File.write(key_path, 'private')
            File.write("#{key_path}.pub", "ssh-ed25519 AAAAgenerated signing@example\n")
        end
    end
end
