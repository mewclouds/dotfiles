# frozen_string_literal: true

require 'open3'

module Dotfiles
    # Runs commands while preserving interactive terminal input when needed.
    class CommandRunner
        # Signals that an external command could not complete successfully.
        class Failure < StandardError
        end

        # Runs a command while capturing its output for inspection.
        #
        # @param command [Array<String>] executable and arguments
        # @return [String] standard output from the command
        # @raise [Failure] when the command exits unsuccessfully
        def capture(command)
            stdout, stderr, status = Open3.capture3(*command)
            unless status.success?
                output = stderr.empty? ? stdout : stderr
                message = if output.strip.empty?
                              "command failed (#{status.exitstatus || 'unknown'}): #{command.join(' ')}"
                          else
                              output
                          end
                raise Failure, message
            end

            stdout
        end

        # Runs a command with the current terminal attached for interaction.
        #
        # @param command [Array<String>] executable and arguments
        # @return [void]
        # @raise [Failure] when the command exits unsuccessfully
        def interactive(command)
            raise Failure, "command failed: #{command.join(' ')}" unless system(*command)
        end
    end
end
