# frozen_string_literal: true

require "fileutils"
require "json"

module Dotfiles
  # Persists successful command executions outside the public repository state.
  class StateStore
    VERSION = 1

    # @param path [String] local JSON state file path
    def initialize(path)
      @path = path
      @actions = load_actions
    end

    # Reports whether an action completed with the current fingerprint.
    #
    # @param action [Dotfiles::Action]
    # @param fingerprint [String] current action fingerprint
    # @return [Boolean]
    def completed?(action, fingerprint)
      entry = @actions[action.id]
      !!(entry && entry["fingerprint"] == fingerprint)
    end

    # Records a successful action and writes the state atomically.
    #
    # @param action [Dotfiles::Action]
    # @param fingerprint [String] fingerprint associated with the execution
    # @return [void]
    def record(action, fingerprint)
      updated_actions = @actions.merge(action.id => {
        "status" => "completed",
        "fingerprint" => fingerprint
      })
      save(updated_actions)
      @actions = updated_actions
    end

    private

    def load_actions
      return {} unless File.file?(@path)

      data = JSON.parse(File.read(@path))
      raise "State file must contain a JSON object." unless data.is_a?(Hash)

      version = data["version"]
      raise "Orchestration state is missing its version." if version.nil?

      raise "Unsupported orchestration state version: #{version}" unless version == VERSION

      actions = data["actions"]
      raise "State file actions must be an object." unless actions.is_a?(Hash)

      actions.each do |action_id, entry|
        valid_entry = entry.is_a?(Hash) &&
          entry["status"] == "completed" &&
          entry["fingerprint"].is_a?(String)
        raise "Invalid orchestration state entry: #{action_id}" unless valid_entry
      end

      actions
    rescue JSON::ParserError => error
      raise "Could not read orchestration state: #{error.message}"
    end

    def save(actions)
      FileUtils.mkdir_p(File.dirname(@path))
      temporary_path = "#{@path}.tmp.#{$$}"
      contents = JSON.pretty_generate("version" => VERSION, "actions" => actions)
      File.write(temporary_path, "#{contents}\n")
      FileUtils.mv(temporary_path, @path)
    ensure
      FileUtils.rm_f(temporary_path) if temporary_path
    end
  end
end
