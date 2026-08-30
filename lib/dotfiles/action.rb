# frozen_string_literal: true

require 'digest'
require 'json'

module Dotfiles
    # Represents one planned state change without coupling it to an implementation.
    class Action
        # Stable identity used to associate an action with local execution state.
        attr_reader :id

        # Identifies the kind of state change the executor should perform.
        attr_reader :name

        # Human-readable explanation shown in plans and status output.
        attr_reader :description

        # Platform to which this action applies.
        attr_reader :platform

        # Values needed to carry out this particular state change.
        attr_reader :parameters

        # Privilege this action needs to run: :admin or :any.
        attr_reader :elevation

        # @param name [Symbol] action type used by the executor
        # @param description [String] human-readable explanation of the action
        # @param id [String, nil] stable identity, defaulting to the action name
        # @param platform [Symbol] platform the action applies to
        # @param parameters [Hash] action-specific data for a future executor
        # @param elevation [Symbol] :admin if the executor must run this with administrator
        #   rights, :any if the current process's privilege level is fine
        def initialize(name:, description:, id: nil, platform: :shared, parameters: {}, elevation: :any)
            @id = (id || name).to_s.freeze
            @name = name
            @description = description
            @platform = platform
            @parameters = parameters.dup.freeze
            @elevation = elevation
        end

        # Creates a deterministic digest of the action definition and its inputs.
        #
        # @param repository_root [String] repository used to resolve input paths
        # @return [String] SHA-256 fingerprint
        def fingerprint(repository_root:)
            input_paths = parameters.fetch(:inputs, [])
            definition = {
                id: id,
                name: name,
                platform: platform,
                parameters: parameters.reject { |key, _| key.to_sym == :inputs },
                inputs: input_fingerprints(input_paths, repository_root)
            }

            Digest::SHA256.hexdigest(JSON.generate(canonicalize(definition)))
        end

        private

        def input_fingerprints(input_paths, repository_root)
            input_paths.to_h do |input_path|
                path = File.expand_path(input_path, repository_root)
                raise "Fingerprint input does not exist: #{path}" unless File.file?(path)

                [input_path, Digest::SHA256.file(path).hexdigest]
            end
        end

        def canonicalize(value)
            case value
            when Hash
                value.each_with_object({}) do |(key, nested_value), result|
                    result[key.to_s] = canonicalize(nested_value)
                end.sort.to_h
            when Array
                value.map { |nested_value| canonicalize(nested_value) }
            when Symbol
                value.to_s
            else
                value
            end
        end
    end
end
