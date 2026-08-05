# frozen_string_literal: true

require "minitest/autorun"
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

  def test_plan_starts_empty
    plan = Dotfiles.plan

    assert_empty plan.actions
    assert plan.empty?
    assert_equal 0, plan.size
  end

  def test_plan_command_reports_empty_plan
    output, error = capture_io do
      assert_equal 0, Dotfiles.run(["plan"])
    end

    assert_empty error
    assert_includes output, "Execution plan"
    assert_includes output, "No actions planned."
  end

  def test_plan_holds_descriptive_actions
    action = Dotfiles::Action.new(
      name: :install_ruby,
      description: "Install Ruby",
      platform: :windows
    )
    plan = Dotfiles::Plan.new.add(action)

    assert_equal 1, plan.size
    assert_equal action, plan.actions.first
    assert_equal :install_ruby, plan.actions.first.name
    assert_equal "Install Ruby", plan.actions.first.description
    assert_equal :windows, plan.actions.first.platform
  end

  def test_plan_actions_cannot_be_modified_through_reader
    plan = Dotfiles::Plan.new

    assert_raises(FrozenError) do
      plan.actions << Dotfiles::Action.new(name: :test, description: "Test")
    end

    assert_empty plan.actions
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
end
