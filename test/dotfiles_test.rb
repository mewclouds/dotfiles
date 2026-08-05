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
