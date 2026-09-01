# frozen_string_literal: true

require 'English'
require 'fileutils'
require 'json'
require 'tmpdir'

module Dotfiles
    # Applies planned state changes and reports the resulting state of each one.
    class Executor
        WINDOWS_POWERSHELL = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
        # Elevates a command through a single UAC prompt without elevating the
        # rest of the run. The command is handed over as a JSON file rather than
        # CLI arguments: PowerShell's parameter binder treats any argument
        # starting with "-" (e.g. "-NoProfile", "-Command") as a potential named
        # parameter, which breaks positional/remaining-argument binding for
        # commands that are themselves PowerShell invocations.
        # The heredoc delimiter is quoted to disable Ruby's escape processing:
        # an unquoted delimiter collapses '\"' to '"' before it ever reaches
        # PowerShell, silently breaking the embedded-quote escaping below.
        ELEVATOR_SCRIPT = <<~'POWERSHELL'
            param([Parameter(Mandatory = $true)][string]$PayloadPath)

            $payload = Get-Content -Raw -Path $PayloadPath | ConvertFrom-Json

            # Start-Process's -ArgumentList does not quote array elements that
            # contain spaces, so a multi-word argument (e.g. a "-Command" script)
            # gets split into separate tokens for the child process. Quoting each
            # element and joining into one string avoids that.
            $quotedArguments = @($payload.arguments) | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }
            $startParameters = @{
                FilePath = $payload.file_path
                ArgumentList = ($quotedArguments -join ' ')
                Verb = 'RunAs'
                Wait = $true
                PassThru = $true
            }
            if ($payload.working_directory) {
                $startParameters.WorkingDirectory = $payload.working_directory
            }
            $process = Start-Process @startParameters
            exit $process.ExitCode
        POWERSHELL

        # @param repository_root [String] absolute repository path
        # @param home_directory [String] destination home directory
        # @param clean [Boolean] whether existing regular files may be removed
        # @param state_path [String] local command execution state path
        def initialize(repository_root:, home_directory: Dir.home, clean: false,
                       state_path: File.join(repository_root, '.local', 'state.json'))
            @repository_root = repository_root
            @home_directory = home_directory
            @clean = clean
            @state_store = StateStore.new(state_path)
            @elevator_script_path = File.join(Dir.tmpdir, 'dotfiles-elevate.ps1')
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
                command_status(action)
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
            create_symlink(source, target, action.elevation)
            :linked
        end

        def create_symlink(source, target, elevation)
            return File.symlink(source, target) unless elevation == :admin

            # Windows only grants SeCreateSymbolicLinkPrivilege to standard users
            # when Developer Mode is on, so this machine needs elevation for it.
            #
            # The paths are embedded directly in the script text rather than
            # passed as trailing arguments: "-Command" does not bind trailing
            # CLI arguments to $args the way "-File" does, so they would
            # otherwise be silently ignored instead of reaching New-Item.
            script = "New-Item -ItemType SymbolicLink -Path '#{powershell_quote(target)}' " \
                     "-Target '#{powershell_quote(source)}' -Force | Out-Null"
            command = [WINDOWS_POWERSHELL, '-NoProfile', '-Command', script]
            return if run_elevated(command)

            raise "Elevated symlink creation failed: #{target}"
        end

        def powershell_quote(value)
            value.gsub("'", "''")
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
            return :already_copied if File.file?(target) && !File.symlink?(target) && FileUtils.compare_file(source,
                                                                                                             target)

            FileUtils.mkdir_p(File.dirname(target))
            FileUtils.rm_f(target)
            FileUtils.cp(source, target)
            :copied
        end

        def copy_status(action)
            source, target = file_paths(action)

            return :missing_source unless File.file?(source)
            return :pending unless File.file?(target) && !File.symlink?(target)

            FileUtils.compare_file(source, target) ? :already_copied : :pending
        end

        def run_command(action)
            # Desired state is trusted repository code, so validation only protects the
            # command shape for now.
            command = action.parameters.fetch(:command)
            validate_command(command)
            fingerprint = action.fingerprint(repository_root: @repository_root)
            return :already_applied if @state_store.completed?(action, fingerprint)

            succeeded = if action.elevation == :admin
                            run_elevated(command)
                        else
                            system(*command, chdir: @repository_root)
                        end

            unless succeeded
                exit_code = $CHILD_STATUS.exitstatus || 'unknown'
                raise "Command failed with exit code #{exit_code}: #{command.join(' ')}"
            end

            @state_store.record(action, fingerprint)
            :executed
        end

        # Runs a command with a single UAC prompt, regardless of whether the
        # current process is already elevated. Start-Process auto-approves
        # elevation requests from an already-elevated parent, so this is safe
        # to call unconditionally rather than branching on current privilege.
        def run_elevated(command)
            resolved_command = command.each_with_index.map do |argument, index|
                if index.positive? && command[index - 1] == '-File'
                    File.expand_path(argument, @repository_root)
                else
                    argument
                end
            end
            payload_path = File.join(Dir.tmpdir, "dotfiles-elevate-#{$PROCESS_ID}.json")
            payload = {
                'file_path' => resolved_command.first,
                'arguments' => resolved_command.drop(1),
                'working_directory' => @repository_root
            }
            File.write(payload_path, JSON.generate(payload))
            File.write(@elevator_script_path, ELEVATOR_SCRIPT)
            system(WINDOWS_POWERSHELL, '-NoProfile', '-ExecutionPolicy',
                   'Bypass', '-File', @elevator_script_path, '-PayloadPath', payload_path)
        ensure
            FileUtils.rm_f(payload_path) if payload_path
        end

        def command_status(action)
            fingerprint = action.fingerprint(repository_root: @repository_root)
            @state_store.completed?(action, fingerprint) ? :already_applied : :planned
        end

        def validate_command(command)
            return if command.is_a?(Array) && !command.empty? && command.all?(String)

            raise ArgumentError, 'Command must be a non-empty array of strings.'
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

            relative_target = target.sub(%r{\A~[\\/]}, '')
            return File.join(@home_directory, relative_target) if relative_target != target

            File.expand_path(target)
        end
    end
end
