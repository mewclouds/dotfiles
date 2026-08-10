# frozen_string_literal: true

require "fileutils"

module Dotfiles
  # Applies planned state changes and reports the resulting state of each one.
  class Executor
    # @param repository_root [String] absolute repository path
    # @param home_directory [String] destination home directory
    # @param clean [Boolean] whether existing regular files may be removed
    def initialize(repository_root:, home_directory: Dir.home, clean: false)
      @repository_root = repository_root
      @home_directory = home_directory
      @clean = clean
    end

    # Applies every selected state change in order.
    #
    # @param plan [Dotfiles::Plan]
    # @return [Array<Symbol>] results for each executed action
    def execute(plan)
      plan.actions.map { |action| execute_action(action) }
    end

    # Describes whether a state change is satisfied, pending, blocked, or unsupported.
    #
    # @param action [Dotfiles::Action]
    # @return [Symbol]
    def status(action)
      case action.name
      when :link_file
        link_status(action)
      when :copy_file
        copy_status(action)
      when :run_command
        :planned
      else
        :unsupported
      end
    end

    private

    def execute_action(action)
      case action.name
      when :link_file
        link_file(action)
      when :copy_file
        copy_file(action)
      when :run_command
        run_command(action)
      else
        raise "Unsupported action: #{action.name}"
      end
    end

    def link_file(action)
      source, target = file_paths(action)

      raise "Source file does not exist: #{source}" unless File.file?(source)

      if File.symlink?(target)
        current_target = begin
          File.realpath(target)
        rescue Errno::ENOENT
          nil
        end
        return :already_linked if current_target == File.realpath(source)

        File.delete(target)
      elsif File.exist?(target)
        raise "Refusing to replace existing file: #{target}" unless @clean

        raise "Refusing to remove existing non-file path: #{target}" unless File.file?(target)

        File.delete(target)
      end

      FileUtils.mkdir_p(File.dirname(target))
      File.symlink(source, target)
      :linked
    end

    def link_status(action)
      source, target = file_paths(action)

      return :missing_source unless File.file?(source)
      return :pending unless File.exist?(target) || File.symlink?(target)
      return :blocked unless File.symlink?(target)

      current_target = begin
        File.realpath(target)
      rescue Errno::ENOENT
        nil
      end

      return :linked if current_target == File.realpath(source)

      :replaceable
    end

    def copy_file(action)
      source, target = file_paths(action)

      raise "Source file does not exist: #{source}" unless File.file?(source)
      raise "Refusing to replace existing non-file path: #{target}" if File.directory?(target)

      FileUtils.mkdir_p(File.dirname(target))
      FileUtils.rm_f(target)
      FileUtils.cp(source, target)
      :copied
    end

    def copy_status(action)
      source, target = file_paths(action)

      return :missing_source unless File.file?(source)
      return :pending unless File.file?(target) && !File.symlink?(target)

      FileUtils.compare_file(source, target) ? :copied : :pending
    end

    def run_command(action)
      # Desired state is trusted repository code, so validation only protects the
      # command shape for now.
      command = action.parameters.fetch(:command)
      validate_command(command)
      return :executed if system(*command)

      exit_code = $?.exitstatus || "unknown"
      raise "Command failed with exit code #{exit_code}: #{command.join(" ")}"
    end

    def validate_command(command)
      return if command.is_a?(Array) && !command.empty? && command.all? { |part| part.is_a?(String) }

      raise ArgumentError, "Command must be a non-empty array of strings."
    end

    def file_paths(action)
      source = File.expand_path(action.parameters.fetch(:source), @repository_root)
      target = expand_target(action.parameters.fetch(:target))
      [source, target]
    end

    def expand_target(target)
      target = target.gsub(/%([^%]+)%/) do
        variable = Regexp.last_match(1)
        ENV.fetch(variable) { raise "Environment variable is not set: #{variable}" }
      end

      relative_target = target.sub(/\A~[\\\/]/, "")
      return File.join(@home_directory, relative_target) if relative_target != target

      File.expand_path(target)
    end
  end
end
