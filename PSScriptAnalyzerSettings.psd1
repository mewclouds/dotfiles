@{
    # ---------------------------------------------------------------------
    # Severity levels to include when running Invoke-ScriptAnalyzer
    # ---------------------------------------------------------------------
    Severity = @('Error', 'Warning', 'Information')

    # ------------------------------------------------------------
    # Rules suppressed repo-wide with explicit justification.
    # These are not oversights - each exclusion is deliberate.
    # ------------------------------------------------------------
    #
    # PSAvoidUsingWriteHost
    #   All scripts here are interactive terminal utilities or
    #   one-shot setup/admin scripts, not reusable library code.
    #   Write-Host is the correct tool because:
    #     1. Coloured output (-ForegroundColor) requires it; neither
    #        Write-Output nor Write-Information support colour.
    #     2. These scripts are never consumed as pipeline input by a
    #        caller, so polluting the success stream is not a concern.
    #     3. ANSI-coloured output via mccoloring() also goes through
    #        Write-Host deliberately to target the display layer.
    #
    # PSAvoidUsingInvokeExpression
    #   This is a dotfiles and machine-setup repository. Invoke-Expression
    #   (IEX) is the standard, documented pattern for bootstrapping tools
    #   that emit shell init code (e.g. fnm, oh-my-posh, starship). It is
    #   also inherently required when fetching and executing configuration
    #   or init scripts from remote sources during setup. The risk profile
    #   for IEX in a personal dotfiles repo is accepted and understood.
    #
    # PSUseShouldProcessForStateChangingFunctions
    #   These scripts are one-off setup/admin tools for personal dotfiles,
    #   not reusable modules. Dry-running a setup script is generally not
    #   needed or practical, so ShouldProcess boilerplate is omitted.
    # ------------------------------------------------------------
    ExcludeRules = @(
        'PSAvoidUsingWriteHost'
        'PSAvoidUsingInvokeExpression'
        'PSUseShouldProcessForStateChangingFunctions'
    )

    # ---------------------------------------------------------------------
    # Use every default rule that ships with PSScriptAnalyzer, then layer
    # our own overrides in Rules below. Set to $false if you'd rather
    # opt-in rule-by-rule instead.
    # ---------------------------------------------------------------------
    IncludeDefaultRules = $true

    Rules = @{

        # ------------------------------------------------------------
        # Formatting: indentation (default PowerShell style -> spaces, size 4)
        # ------------------------------------------------------------
        PSUseConsistentIndentation = @{
            Enable = $true
            Kind = 'space'
            IndentationSize = 4
            PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
        }

        # ------------------------------------------------------------
        # Formatting: whitespace around operators, braces, separators
        # ------------------------------------------------------------
        PSUseConsistentWhitespace = @{
            Enable = $true
            CheckInnerBrace = $true
            CheckOpenBrace = $true
            CheckOpenParen = $true
            CheckOperator = $true
            CheckPipe = $true
            CheckPipeForRedundantWhitespace = $false
            CheckSeparator = $true
            CheckParameter = $false
            IgnoreAssignmentOperatorInsideHashTable = $false
        }

        # ------------------------------------------------------------
        # Formatting: brace placement -> OTBS (default PowerShell style)
        # ------------------------------------------------------------
        PSPlaceOpenBrace = @{
            Enable = $true
            OnSameLine = $true
            NewLineAfter = $true
            IgnoreOneLineBlock = $true
        }

        PSPlaceCloseBrace = @{
            Enable = $true
            NewLineAfter = $false
            IgnoreOneLineBlock = $true
            NoEmptyLineBefore = $true
        }

        # ------------------------------------------------------------
        # Line length -> max_line_length = 120 from .editorconfig
        # ------------------------------------------------------------
        PSAvoidLongLines = @{
            Enable = $true
            MaximumLineLength = 120
        }

        # ------------------------------------------------------------
        # Trailing newline / trailing whitespace
        # (reinforces editorconfig at the analyzer level)
        # ------------------------------------------------------------
        PSAvoidTrailingWhitespace = @{
            Enable = $true
        }

        PSUseCorrectCasing = @{
            Enable = $true
        }
    }
}
