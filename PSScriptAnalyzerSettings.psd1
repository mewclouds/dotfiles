@{
    Severity = @('Error', 'Warning', 'Information')

    ExcludeRules = @(
        'PSAvoidUsingWriteHost'
        'PSAvoidUsingInvokeExpression'
        'PSUseShouldProcessForStateChangingFunctions'
        # Intermittent NullReferenceException from CommandInfo.get_Parameters();
        # see https://github.com/PowerShell/PSScriptAnalyzer/issues/1708
        'PSUseCorrectCasing'
    )

    IncludeDefaultRules = $true

    Rules = @{
        PSUseConsistentIndentation = @{
            Enable = $true
            Kind = 'space'
            IndentationSize = 4
            PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
        }

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

        PSAvoidLongLines = @{
            Enable = $true
            MaximumLineLength = 120
        }

        PSAvoidTrailingWhitespace = @{
            Enable = $true
        }
    }
}
