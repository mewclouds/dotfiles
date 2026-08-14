# frozen_string_literal: true

require "fileutils"
require "io/console"
require "json"
require "tmpdir"
require_relative "command_runner"

module Dotfiles
  # Coordinates decryption and extraction of the encrypted private-state archive.
  class PrivateState
    BITWARDEN_ITEM_NAME = "dotfiles-age-keys"

    # @param repository_root [String] repository root path
    # @param input [IO] source for interactive responses
    # @param output [IO] destination for status messages
    # @param runner [#capture, #interactive] command execution dependency
    # @param private_directory [String] destination directory for private state
    # @param archive_path [String] path to the encrypted private archive
    def initialize(
      repository_root:,
      input: $stdin,
      output: $stdout,
      runner: CommandRunner.new,
      private_directory: File.join(repository_root, "private"),
      archive_path: File.join(repository_root, "private.age")
    )
      @repository_root = repository_root
      @input = input
      @output = output
      @runner = runner
      @private_directory = private_directory
      @archive_path = archive_path
      @session_key = ENV["BW_SESSION"]
    end

    # Reports whether the private state directory already exists and contains files.
    #
    # @return [Boolean]
    def present?
      Dir.exist?(@private_directory) && !Dir.empty?(@private_directory)
    end

    # Reports whether an encrypted private archive file exists in the repository.
    #
    # @return [Boolean]
    def archive_exist?
      File.file?(@archive_path)
    end

    # Decrypts and extracts the private archive if not already present.
    #
    # @return [Symbol] :already_present, :missing_archive, or :decrypted
    def decrypt
      # Existing decrypted private workspace files are never overwritten to avoid
      # discarding local uncommitted changes or machine-specific edits.
      if present?
        @output.puts "Private state already present; skipping decryption."
        return :already_present
      end

      return :missing_archive unless archive_exist?

      identity = retrieve_identity
      begin
        Dir.mktmpdir("dotfiles-decrypt-") do |temp_dir|
          temporary_identity_path = File.join(temp_dir, "identity.txt")
          temporary_archive_path = File.join(temp_dir, "archive")

          # age expects an identity file on disk for decryption. Writing the temporary identity
          # inside a restricted temporary directory prevents permission leaks on multi-user systems.
          File.write(temporary_identity_path, identity, perm: 0o600)
          @output.puts "Decrypting private state from #{File.basename(@archive_path)}..."

          @runner.capture([
            "age", "--decrypt",
            "-i", temporary_identity_path,
            "-o", temporary_archive_path,
            @archive_path
          ])

          extract_archive(temporary_archive_path)
          @output.puts "Private state decrypted successfully."
        end
      rescue CommandRunner::Failure => error
        raise "Failed to decrypt private state archive '#{File.basename(@archive_path)}'.\n#{error.message}"
      end

      :decrypted
    end

    private

    # Retrieves the private age identity note from Bitwarden.
    #
    # @return [String] age secret key
    def retrieve_identity
      ensure_authenticated_and_unlocked
      command = ["bw", "get", "notes", BITWARDEN_ITEM_NAME]
      command += ["--session", @session_key] if @session_key
      identity = @runner.capture(command).strip
      if identity.empty?
        raise "Could not retrieve '#{BITWARDEN_ITEM_NAME}' from Bitwarden. The note is empty."
      end

      identity
    rescue CommandRunner::Failure => error
      raise "Bitwarden CLI failed to retrieve '#{BITWARDEN_ITEM_NAME}'.\n#{error.message}"
    end

    # Ensures Bitwarden is logged in and the vault is unlocked before querying notes.
    # Subcommands run through captured pipes, so Bitwarden cannot prompt for passwords
    # on stdin during standard execution.
    def ensure_authenticated_and_unlocked
      status = vault_status

      if status == "unauthenticated"
        @output.puts "Bitwarden is not logged in. Logging in..."
        @runner.interactive(["bw", "login"])
        status = vault_status
      end

      unlock_vault if status == "locked"
    end

    # Queries the current Bitwarden authentication and lock state.
    #
    # @return [String] "unlocked", "locked", "unauthenticated", or "unknown"
    def vault_status
      raw_status = @runner.capture(["bw", "status"])
      JSON.parse(raw_status).fetch("status")
    rescue JSON::ParserError, CommandRunner::Failure
      "unknown"
    end

    # Prompts for the master password and unlocks the Bitwarden vault to obtain a session key.
    # The password is passed via a temporary environment variable rather than process arguments
    # to avoid leaking it in process listings, and is deleted immediately afterward.
    def unlock_vault
      password = ask_password("Bitwarden master password: ")
      raise "Master password cannot be empty." if password.nil? || password.empty?

      ENV["BW_PASSWORD"] = password
      begin
        @session_key = @runner.capture(["bw", "unlock", "--passwordenv", "BW_PASSWORD", "--raw"]).strip
        ENV["BW_SESSION"] = @session_key
      ensure
        ENV.delete("BW_PASSWORD")
      end
    rescue CommandRunner::Failure => error
      raise "Failed to unlock Bitwarden vault. Verify your master password.\n#{error.message}"
    end

    # Reads the master password securely with masked input when connected to a terminal,
    # falling back to standard input reading for non-TTY or automated test streams.
    def ask_password(prompt)
      if @input.is_a?(IO) && @input.respond_to?(:tty?) && @input.tty? && @input.respond_to?(:getpass)
        begin
          return @input.getpass(prompt)
        rescue Errno::EBADF, Errno::ENOTTY, IOError
          # Fall back to standard stream read if TTY handle is unavailable.
        end
      end

      @output.print(prompt)
      @input.gets&.chomp
    end

    # Unpacks the temporary ZIP archive into the destination private directory.
    # Handles both root-relative archives and archives created with a top-level 'private/' directory.
    def extract_archive(archive_path)
      Dir.mktmpdir("dotfiles-extract-") do |temp_dir|
        @runner.capture(["tar", "-xf", archive_path, "-C", temp_dir])

        extracted_private = File.join(temp_dir, "private")
        FileUtils.mkdir_p(@private_directory)

        if Dir.exist?(extracted_private)
          FileUtils.cp_r(File.join(extracted_private, "."), @private_directory)
        else
          FileUtils.cp_r(File.join(temp_dir, "."), @private_directory)
        end
      end
    end
  end
end
