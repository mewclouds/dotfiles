# frozen_string_literal: true

require "json"
require "fileutils"
require "open3"

module Dotfiles
  # Coordinates interactive preparation of machine-local Git signing state.
  class SigningSetup
    DEFAULT_KEY_NAME = "id_ed25519_signing"

    # @param context [Dotfiles::Context] current runtime context
    # @param input [IO] source for interactive responses
    # @param output [IO] destination for prompts and status messages
    # @param home_directory [String] home directory containing the SSH key
    # @param runner [#capture, #interactive] command execution dependency
    def initialize(
      context,
      input: $stdin,
      output: $stdout,
      home_directory: Dir.home,
      runner: CommandRunner.new
    )
      @context = context
      @input = input
      @output = output
      @home_directory = home_directory
      @runner = runner
    end

    # Runs the interactive signing setup without deleting existing keys.
    #
    # @return [void]
    def run
      ensure_github_authentication
      key_path = File.join(@home_directory, ".ssh", DEFAULT_KEY_NAME)

      generate_key(key_path) unless File.file?(key_path)
      return unless File.file?(key_path)

      public_key_path = "#{key_path}.pub"
      upload_key(public_key_path) unless github_has_signing_key?(public_key_path)
      add_key_to_agent(key_path)
    end

    private

    def ensure_github_authentication
      @runner.capture(["gh", "auth", "status"])
    rescue CommandRunner::Failure => error
      raise "GitHub CLI is not authenticated. Run `gh auth login` first.\n#{error.message}"
    end

    def generate_key(key_path)
      return unless ask("No SSH signing key exists. Generate one now?", default: false)

      @key_title ||= ask_text("GitHub key title", default: default_title)
      FileUtils.mkdir_p(File.dirname(key_path))
      @runner.interactive(["ssh-keygen", "-t", "ed25519", "-C", @key_title, "-f", key_path])
    end

    def github_has_signing_key?(public_key_path)
      ensure_github_signing_key_scope
      public_key = File.read(public_key_path).strip
      keys = JSON.parse(@runner.capture(["gh", "api", "user/ssh_signing_keys"]))
      unless keys.is_a?(Array) && keys.all? { |key| key.is_a?(Hash) && key["key"].is_a?(String) }
        raise "GitHub returned an unexpected SSH signing-key response."
      end

      keys.any? { |key| key_material(key["key"]) == key_material(public_key) }
    rescue JSON::ParserError => error
      raise "Could not read the SSH keys returned by GitHub CLI: #{error.message}"
    end

    def ensure_github_signing_key_scope
      # Bootstrap authentication omits this admin scope because it is only needed to manage signing keys.
      @runner.interactive(["gh", "auth", "refresh", "-h", "github.com", "-s", "admin:ssh_signing_key"])
    rescue CommandRunner::Failure => error
      raise "GitHub CLI could not obtain the SSH signing-key permission. " \
        "Run `gh auth refresh -h github.com -s admin:ssh_signing_key` and try again.\n#{error.message}"
    end

    def upload_key(public_key_path)
      return unless ask("Upload this key to GitHub as a signing key?", default: true)

      @key_title ||= ask_text("GitHub key title", default: default_title)
      @runner.capture([
        "gh", "ssh-key", "add", public_key_path,
        "--type", "signing",
        "--title", @key_title
      ])
    end

    def add_key_to_agent(key_path)
      public_key = File.read("#{key_path}.pub").strip
      loaded_keys = loaded_agent_keys

      return if loaded_keys.lines.any? { |line| key_material(line) == key_material(public_key) }

      @runner.interactive(["ssh-add", key_path])
    rescue CommandRunner::Failure => error
      raise "Could not access the SSH agent. Start it and try again.\n#{error.message}"
    end

    def loaded_agent_keys
      @runner.capture(["ssh-add", "-L"])
    rescue CommandRunner::Failure => error
      return "" if error.message.match?(/agent has no identities/i)

      raise
    end

    # SSH comments are labels, so only the algorithm and key material identify the key.
    def key_material(public_key)
      public_key.split.first(2).join(" ")
    end

    def default_title
      "#{@context.platform_name.capitalize} - SSH signing"
    end

    def ask(question, default:)
      suffix = default ? "[Y/n]" : "[y/N]"
      @output.print("#{question} #{suffix} ")
      answer = @input.gets
      return default if answer.nil?

      normalized = answer.strip.downcase
      return default if normalized.empty?

      %w[y yes].include?(normalized)
    end

    def ask_text(question, default:)
      @output.print("#{question} [#{default}]: ")
      answer = @input.gets&.strip
      (answer.nil? || answer.empty?) ? default : answer
    end

    # Runs commands while preserving interactive terminal input when needed.
    class CommandRunner
      # Signals that an external command could not complete successfully.
      Failure = Class.new(StandardError)

      # Runs a command while capturing its output for inspection.
      #
      # @param command [Array<String>] executable and arguments
      # @return [String] standard output from the command
      # @raise [Failure] when the command exits unsuccessfully
      def capture(command)
        stdout, stderr, status = Open3.capture3(*command)
        raise Failure, stderr.empty? ? stdout : stderr unless status.success?

        stdout
      end

      # Runs a command with the current terminal attached for interaction.
      #
      # @param command [Array<String>] executable and arguments
      # @return [void]
      # @raise [Failure] when the command exits unsuccessfully
      def interactive(command)
        raise Failure, "command failed: #{command.join(" ")}" unless system(*command)
      end
    end
  end
end
