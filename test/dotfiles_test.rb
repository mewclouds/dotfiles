# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "json"
require "stringio"
require "tmpdir"
require_relative "../lib/dotfiles"

class DotfilesTest < Minitest::Test
  def test_status_reports_runtime_context
    output, error = capture_io do
      assert_equal 0, Dotfiles.run(["status"])
    end

    assert_empty error
    assert_includes output, "Dotfiles orchestrator"
    assert_includes output, "Platform:"
    assert_includes output, "Ruby: #{RUBY_VERSION}"
    assert_includes output, "Repository: #{Dotfiles.repository_root}"
  end

  def test_platform_includes_a_friendly_name_and_host_identifier
    assert_match(/\A(?:windows|linux|unknown) \(.+\)\z/, Dotfiles.platform)
  end

  def test_context_contains_runtime_information
    context = Dotfiles::Context.new(
      host_os: "linux-gnu",
      ruby_version: "4.0.0",
      repository_root: "/tmp/dotfiles"
    )

    assert_equal "linux", context.platform_name
    assert_equal "linux (linux-gnu)", context.platform
    assert_equal "4.0.0", context.ruby_version
    assert_equal "/tmp/dotfiles", context.repository_root
  end

  def test_context_classifies_windows_hosts
    context = Dotfiles::Context.new(host_os: "mingw32")

    assert_equal "windows", context.platform_name
  end

  def test_plan_contains_shared_configuration_actions
    context = Dotfiles::Context.new(host_os: "mingw32")
    plan = Dotfiles::Plan.new(Dotfiles::DesiredState.new(context).actions)
      .for_platform(context.platform_name)

    assert_equal 6, plan.size
    assert_equal :link_file, plan.actions[0].name
    assert_equal ".config/.gitconfig", plan.actions[0].parameters[:source]
    assert_equal "~/.gitconfig", plan.actions[0].parameters[:target]
    assert_equal :link_file, plan.actions[1].name
    assert_equal ".config/mise/config.toml", plan.actions[1].parameters[:source]
    assert_equal "~/.config/mise/config.toml", plan.actions[1].parameters[:target]
    assert_equal :link_file, plan.actions[2].name
    assert_equal :windows, plan.actions[2].platform
    assert_equal ".config/fastfetch-win.jsonc", plan.actions[2].parameters[:source]
    assert_equal "%USERPROFILE%/.config/fastfetch/config.jsonc", plan.actions[2].parameters[:target]
    assert_equal :copy_file, plan.actions[3].name
    assert_equal :windows, plan.actions[3].platform
    assert_equal ".config/windows-terminal.json", plan.actions[3].parameters[:source]
    assert_equal "%LOCALAPPDATA%/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json",
      plan.actions[3].parameters[:target]
    assert_equal :link_file, plan.actions[4].name
    assert_equal "scripts/shell/profile.ps1", plan.actions[4].parameters[:source]
    assert_equal "%USERPROFILE%/Documents/PowerShell/Microsoft.PowerShell_profile.ps1",
      plan.actions[4].parameters[:target]
    assert_equal :link_file, plan.actions[5].name
    assert_equal "scripts/shell/ProfileExtensions.ps1", plan.actions[5].parameters[:source]
    assert_equal "%USERPROFILE%/Documents/PowerShell/ProfileExtensions.ps1",
      plan.actions[5].parameters[:target]
  end

  def test_plan_command_reports_shared_configuration
    output, error = capture_io do
      assert_equal 0, Dotfiles.run(["plan"])
    end

    assert_empty error
    assert_includes output, "Execution plan"
    assert_includes output, "Apply shared Git configuration"
    assert_includes output, "Apply mise toolchain configuration"
  end

  def test_plan_holds_descriptive_actions
    action = Dotfiles::Action.new(
      name: :install_ruby,
      description: "Install Ruby",
      platform: :windows,
      parameters: {
        source: "install/ruby.ps1",
        target: "~/ruby.ps1"
      }
    )
    plan = Dotfiles::Plan.new.add(action)

    assert_equal 1, plan.size
    assert_equal action, plan.actions.first
    assert_equal :install_ruby, plan.actions.first.name
    assert_equal "Install Ruby", plan.actions.first.description
    assert_equal :windows, plan.actions.first.platform
    assert_equal "install/ruby.ps1", plan.actions.first.parameters[:source]
    assert_equal "~/ruby.ps1", plan.actions.first.parameters[:target]
  end

  def test_plan_actions_cannot_be_modified_through_reader
    plan = Dotfiles::Plan.new

    assert_raises(FrozenError) do
      plan.actions << Dotfiles::Action.new(name: :test, description: "Test")
    end

    assert_empty plan.actions
  end

  def test_plan_filters_platform_specific_actions
    shared = Dotfiles::Action.new(name: :shared, description: "Shared")
    windows = Dotfiles::Action.new(name: :windows, description: "Windows", platform: :windows)
    linux = Dotfiles::Action.new(name: :linux, description: "Linux", platform: :linux)
    plan = Dotfiles::Plan.new([shared, windows, linux])

    assert_equal [shared, windows], plan.for_platform(:windows).actions
    assert_equal [shared, linux], plan.for_platform(:linux).actions
  end

  def test_linux_plan_excludes_windows_fastfetch_configuration
    context = Dotfiles::Context.new(host_os: "linux-gnu")
    plan = Dotfiles::Plan.new(Dotfiles::DesiredState.new(context).actions)
      .for_platform(context.platform_name)

    assert_equal 2, plan.size
    refute plan.actions.any? { |action| action.description.include?("Fastfetch") }
  end

  def test_executor_links_a_file_without_overwriting
    Dir.mktmpdir do |directory|
      source_directory = File.join(directory, "repository")
      home_directory = File.join(directory, "home")
      FileUtils.mkdir_p(source_directory)
      File.write(File.join(source_directory, "config"), "value\n")

      action = Dotfiles::Action.new(
        name: :link_file,
        description: "Link test file",
        parameters: {source: "config", target: "~/config"}
      )

      begin
        result = Dotfiles::Executor.new(
          repository_root: source_directory,
          home_directory: home_directory
        ).execute(Dotfiles::Plan.new([action]))
      rescue SystemCallError => error
        skip "Symlinks are unavailable: #{error.message}"
      end

      assert_equal [:linked], result
      target = File.join(home_directory, "config")
      assert File.symlink?(target)
      assert_equal File.realpath(File.join(source_directory, "config")), File.realpath(target)
    end
  end

  def test_executor_refuses_to_replace_a_regular_file
    Dir.mktmpdir do |directory|
      source_directory = File.join(directory, "repository")
      home_directory = File.join(directory, "home")
      FileUtils.mkdir_p(source_directory)
      FileUtils.mkdir_p(home_directory)
      File.write(File.join(source_directory, "config"), "new\n")
      File.write(File.join(home_directory, "config"), "old\n")

      action = Dotfiles::Action.new(
        name: :link_file,
        description: "Link test file",
        parameters: {source: "config", target: "~/config"}
      )

      executor = Dotfiles::Executor.new(
        repository_root: source_directory,
        home_directory: home_directory
      )

      error = assert_raises(RuntimeError) do
        executor.execute(Dotfiles::Plan.new([action]))
      end
      assert_match(/Refusing to replace/, error.message)
      assert_equal "old\n", File.read(File.join(home_directory, "config"))
    end
  end

  def test_executor_reports_pending_link
    Dir.mktmpdir do |directory|
      source_directory = File.join(directory, "repository")
      home_directory = File.join(directory, "home")
      FileUtils.mkdir_p(source_directory)
      File.write(File.join(source_directory, "config"), "value\n")

      action = Dotfiles::Action.new(
        name: :link_file,
        description: "Link test file",
        parameters: {source: "config", target: "~/config"}
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
      source_directory = File.join(directory, "repository")
      home_directory = File.join(directory, "home")
      FileUtils.mkdir_p(source_directory)
      FileUtils.mkdir_p(home_directory)
      File.write(File.join(source_directory, "settings.json"), "desired\n")
      File.write(File.join(home_directory, "settings.json"), "default\n")

      action = Dotfiles::Action.new(
        name: :copy_file,
        description: "Copy test file",
        parameters: {source: "settings.json", target: "~/settings.json"}
      )

      result = Dotfiles::Executor.new(
        repository_root: source_directory,
        home_directory: home_directory
      ).execute(Dotfiles::Plan.new([action]))

      assert_equal [:copied], result
      assert_equal "desired\n", File.read(File.join(home_directory, "settings.json"))
    end
  end

  def test_executor_force_copies_a_file_over_an_existing_symlink
    Dir.mktmpdir do |directory|
      source_directory = File.join(directory, "repository")
      home_directory = File.join(directory, "home")
      other_directory = File.join(directory, "other")
      FileUtils.mkdir_p(source_directory)
      FileUtils.mkdir_p(home_directory)
      FileUtils.mkdir_p(other_directory)
      File.write(File.join(source_directory, "settings.json"), "desired\n")
      File.write(File.join(other_directory, "settings.json"), "linked\n")

      target = File.join(home_directory, "settings.json")
      begin
        File.symlink(File.join(other_directory, "settings.json"), target)
      rescue SystemCallError => error
        skip "Symlinks are unavailable: #{error.message}"
      end

      action = Dotfiles::Action.new(
        name: :copy_file,
        description: "Copy test file",
        parameters: {source: "settings.json", target: "~/settings.json"}
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
      source_directory = File.join(directory, "repository")
      home_directory = File.join(directory, "home")
      FileUtils.mkdir_p(source_directory)
      FileUtils.mkdir_p(home_directory)
      File.write(File.join(source_directory, "config"), "new\n")
      File.write(File.join(home_directory, "config"), "old\n")

      action = Dotfiles::Action.new(
        name: :link_file,
        description: "Link test file",
        parameters: {source: "config", target: "~/config"}
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
      source_directory = File.join(directory, "repository")
      home_directory = File.join(directory, "home")
      FileUtils.mkdir_p(source_directory)
      FileUtils.mkdir_p(home_directory)
      File.write(File.join(source_directory, "config"), "new\n")
      File.write(File.join(home_directory, "config"), "old\n")

      action = Dotfiles::Action.new(
        name: :link_file,
        description: "Link test file",
        parameters: {source: "config", target: "~/config"}
      )

      begin
        result = Dotfiles::Executor.new(
          repository_root: source_directory,
          home_directory: home_directory,
          clean: true
        ).execute(Dotfiles::Plan.new([action]))
      rescue SystemCallError => error
        skip "Symlinks are unavailable: #{error.message}"
      end

      assert_equal [:linked], result
      target = File.join(home_directory, "config")
      assert File.symlink?(target)
      assert_equal "new\n", File.read(target)
    end
  end

  def test_clean_option_accepts_both_cli_spellings
    assert Dotfiles.clean_option(["--clean"])
    assert Dotfiles.clean_option(["-Clean"])
    refute Dotfiles.clean_option([])
  end

  def test_signing_setup_generates_uploads_and_loads_a_new_key
    Dir.mktmpdir do |directory|
      runner = FakeCommandRunner.new(empty_agent: true)
      context = Dotfiles::Context.new(host_os: "mingw32")
      input = StringIO.new("y\nWindows Desktop\n")

      Dotfiles::SigningSetup.new(
        context,
        input: input,
        output: StringIO.new,
        home_directory: directory,
        runner: runner
      ).run

      assert_includes runner.commands, ["gh", "ssh-key", "add",
        File.join(directory, ".ssh", "id_ed25519_signing.pub"),
        "--type", "signing", "--title", "Windows Desktop"]
      assert_includes runner.commands, ["ssh-add", File.join(directory, ".ssh", "id_ed25519_signing")]
    end
  end

  def test_signing_setup_does_not_upload_or_reload_an_existing_key
    Dir.mktmpdir do |directory|
      key_path = File.join(directory, ".ssh", "id_ed25519_signing")
      public_key = "ssh-ed25519 AAAAexisting local-comment"
      FileUtils.mkdir_p(File.dirname(key_path))
      File.write(key_path, "private")
      File.write("#{key_path}.pub", "#{public_key}\n")

      runner = FakeCommandRunner.new(
        github_key: "ssh-ed25519 AAAAexisting github-comment",
        loaded_key: "ssh-ed25519 AAAAexisting agent-comment"
      )
      Dotfiles::SigningSetup.new(
        Dotfiles::Context.new(host_os: "mingw32"),
        input: StringIO.new,
        output: StringIO.new,
        home_directory: directory,
        runner: runner
      ).run

      refute runner.commands.any? { |command| command.first(3) == ["gh", "ssh-key", "add"] }
      refute runner.commands.include?(["ssh-add", File.join(directory, ".ssh", "id_ed25519_signing")])
    end
  end

  def test_signing_setup_rejects_an_invalid_github_key_response
    Dir.mktmpdir do |directory|
      key_path = File.join(directory, ".ssh", "id_ed25519_signing")
      FileUtils.mkdir_p(File.dirname(key_path))
      File.write(key_path, "private")
      File.write("#{key_path}.pub", "ssh-ed25519 AAAAexisting local-comment\n")

      runner = FakeCommandRunner.new(github_response: "{}")
      error = assert_raises(RuntimeError) do
        Dotfiles::SigningSetup.new(
          Dotfiles::Context.new(host_os: "mingw32"),
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
      description: "Install a tool",
      parameters: {tool: "ruby"}
    )

    assert_raises(FrozenError) do
      action.parameters[:tool] = "python"
    end

    assert_equal "ruby", action.parameters[:tool]
  end

  def test_repository_root_is_based_on_the_library_location
    expected_root = File.expand_path("..", __dir__)

    assert_equal expected_root, Dotfiles.repository_root
  end

  def test_run_defaults_to_status
    output, = capture_io do
      assert_equal 0, Dotfiles.run
    end

    assert_includes output, "Dotfiles orchestrator"
  end

  def test_unknown_commands_raise_an_error
    error = assert_raises(RuntimeError) do
      Dotfiles.run(["unknown"])
    end

    assert_equal "Unknown command: unknown", error.message
  end

  class FakeCommandRunner
    attr_reader :commands

    def initialize(github_key: nil, loaded_key: "", empty_agent: false, github_response: nil)
      @github_key = github_key
      @loaded_key = loaded_key
      @empty_agent = empty_agent
      @github_response = github_response
      @commands = []
    end

    def capture(command)
      @commands << command
      return "" if command == ["gh", "auth", "status"]
      if command == ["gh", "api", "user/ssh_signing_keys"] && @github_response
        return @github_response
      end
      return [{"key" => @github_key}].to_json if command == ["gh", "api", "user/ssh_signing_keys"] && @github_key
      return "[]" if command == ["gh", "api", "user/ssh_signing_keys"]
      if command == ["ssh-add", "-L"]
        raise Dotfiles::SigningSetup::CommandRunner::Failure, "The agent has no identities." if @empty_agent

        return @loaded_key
      end

      ""
    end

    def interactive(command)
      @commands << command
      if command.first == "ssh-keygen"
        key_path = command.last
        FileUtils.mkdir_p(File.dirname(key_path))
        File.write(key_path, "private")
        File.write("#{key_path}.pub", "ssh-ed25519 AAAAgenerated signing@example\n")
      end
    end
  end
end
