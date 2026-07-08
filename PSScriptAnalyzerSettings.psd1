@{
	# ---------------------------------------------------------------------
	# Severity levels to include when running Invoke-ScriptAnalyzer
	# ---------------------------------------------------------------------
	Severity            = @('Error', 'Warning', 'Information')

	# ---------------------------------------------------------------------
	# Use every default rule that ships with PSScriptAnalyzer, then layer
	# our own overrides in Rules below. Set to $false if you'd rather
	# opt-in rule-by-rule instead.
	# ---------------------------------------------------------------------
	IncludeDefaultRules = $true

	Rules               = @{

		# ------------------------------------------------------------
		# Formatting: indentation (default PowerShell style -> spaces, size 4)
		# ------------------------------------------------------------
		PSUseConsistentIndentation = @{
			Enable              = $true
			Kind                = 'space'
			IndentationSize     = 4
			PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
		}

		# ------------------------------------------------------------
		# Formatting: whitespace around operators, braces, separators
		# ------------------------------------------------------------
		PSUseConsistentWhitespace  = @{
			Enable                                  = $true
			CheckInnerBrace                         = $true
			CheckOpenBrace                          = $true
			CheckOpenParen                          = $true
			CheckOperator                           = $true
			CheckPipe                               = $true
			CheckPipeForRedundantWhitespace         = $false
			CheckSeparator                          = $true
			CheckParameter                          = $false
			IgnoreAssignmentOperatorInsideHashTable = $false
		}

		# ------------------------------------------------------------
		# Formatting: brace placement -> OTBS (default PowerShell style)
		# ------------------------------------------------------------
		PSPlaceOpenBrace           = @{
			Enable             = $true
			OnSameLine         = $true
			NewLineAfter       = $true
			IgnoreOneLineBlock = $true
		}

		PSPlaceCloseBrace          = @{
			Enable             = $true
			NewLineAfter       = $false
			IgnoreOneLineBlock = $true
			NoEmptyLineBefore  = $true
		}

		# ------------------------------------------------------------
		# Line length -> max_line_length = 120 from .editorconfig
		# ------------------------------------------------------------
		PSAvoidLongLines           = @{
			Enable            = $true
			MaximumLineLength = 120
		}

		# ------------------------------------------------------------
		# Trailing newline / trailing whitespace
		# (reinforces editorconfig at the analyzer level)
		# ------------------------------------------------------------
		PSAvoidTrailingWhitespace  = @{
			Enable = $true
		}

		PSUseCorrectCasing         = @{
			Enable = $true
		}
	}
}
