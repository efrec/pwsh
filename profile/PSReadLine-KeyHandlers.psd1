#-- PSReadLine-KeyHandlers.psd1 -------------------------------------------------------------------#
# This was too long to keep in my profile. Now it's in data format. Get configured, nerd.

# Hashtable of sets (arrays) of key handlers.
# Each set can be applied separately by splatting each key handler to PSReadLine.

$PSReadLineKeyHandlers = @{
    SmartInsertDelete = @(
        @{
            Chord            = '"', "'"
            BriefDescription = 'InsertPairedQuote'
            LongDescription  = 'Insert paired quotes if not already inside a quoted string. Swap single/double quotes with a string selected.'
            ScriptBlock      = {
                param($key, $arg)

                #-- Initialization ----------------------------------------------------------------#

                $mark = $key.KeyChar <# A single or double (dumb) quotation mark. #>

                $ast = $tokens = $parseErrors = $null
                [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$ast, [ref]$tokens, [ref]$parseErrors, [ref]$null)
                $selectionStart = $selectionLength = $null
                [Microsoft.PowerShell.PSConsoleReadLine]::GetSelectionState([ref]$selectionStart, [ref]$selectionLength)
                $line = $cursor = $null
                [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

                #-- Functions ---------------------------------------------------------------------#

                function Get-TokenFromCursorPSRL {
                    param($tokens, $cursor)
                    foreach ($token in $tokens) {
                        if ($cursor -lt $token.Extent.StartOffset) { continue }
                        if ($cursor -lt $token.Extent.EndOffset) {
                            $result = $token
                            if ($token = $token -as [StringExpandableToken]) {
                                $nested = Get-TokenFromCursorPSRL $token.NestedTokens $cursor
                                if ($nested) { $result = $nested }
                            }
                            return $result
                        }
                    }
                    return $null
                }

                function Get-TokenFromSelectionPSRL {
                    param($tokens, $start, $length)
                    $end = $start + $length
                    foreach ($token in $tokens) {
                        if ($start -lt $token.Extent.StartOffset) { continue }
                        if ($start -lt $token.Extent.EndOffset) {
                            $result = $token
                            if ($end -eq $result.Extent.EndOffset) { return $result }
                            if ($token = $token -as [StringExpandableToken]) {
                                $nested = Get-TokenFromSelectionPSRL $token.NestedTokens $start $length
                                if ($nested) { $result = $nested }
                            }
                            if (
                                $start -eq $result.Extent.StartOffset -and
                                $end -eq $result.Extent.EndOffset
                            ) { return $result }
                        }
                    }
                    return $null
                }

                #-- Process -----------------------------------------------------------------------#

                # Handle the case when text is selected
                if ($selectionStart -ne -1) {
                    # When only a (matching) quotation mark is selected, move past it.
                    if ($selectionLength -eq 1 -and $line[$selectionStart] -eq $mark) {
                        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($selectionStart + 1)
                        return
                    }

                    # Wrap selection in quotes and move cursor to end.
                    if ($selectionToken = Get-TokenFromSelectionPSRL $tokens $selectionStart $selectionLength) {
                        $pattern = "^|$"
                        $replace = "$mark"
                        $offset = 2
                        # Or wrap quotes around selected string iff the marks are mismatched
                        if ($selectionToken -is [StringToken]) {
                            $pattern = '\A([''"])(.*)(\1)\z'
                            $replace = "$mark`$2$mark"
                            $offset = 0
                        }

                        [Microsoft.PowerShell.PSConsoleReadLine]::Replace(
                            $selectionStart,
                            $selectionLength,
                            [regex]::Replace($line.SubString($selectionStart, $selectionLength), $pattern, $replace)
                        )
                        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($selectionStart + $selectionLength + $offset)
                        return
                    }

                    # Insert the mark normally, replacing the entire selection.
                    [Microsoft.PowerShell.PSConsoleReadLine]::SelfInsert($key, $arg)
                    return
                }

                # No text is selected; handle the typical case.
                $token = Get-TokenFromCursorPSRL $tokens $cursor

                # Use smart quoting when adjacent to/inside of a string.
                if ($token -is [StringToken] -and $token.Kind -ne [TokenKind]::Generic) {
                    # When at the start of a quoted string, we may have options:
                    # (1) start a new, empty string before it?
                    # todo: Check for and handle smart lists and dicts, e.g.:
                    # todo: 'a', 'b', (cursor here)'d' => type ['] => 'a', 'b', '', 'd'
                    if ($token.Extent.StartOffset -eq $cursor) {
                        # Use separate inserts to let the user Ctrl+Z out of "unexpected smart behavior".
                        [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$mark")
                        [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$mark ")
                        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
                        return
                    }

                    # When at the end of a quoted string, and the marks match, move cursor past the mark.
                    if ($token.Extent.EndOffset -eq ($cursor + 1) -and $line[$cursor] -eq $mark) {
                        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
                        return
                    }
                }

                # If cursor is at the start of certain tokens, enclose the token in quotes.
                # todo: move to a Ctrl+["'] key handler for cycling quote/unquote
                if ($token.Extent.StartOffset -eq $cursor) {
                    if ($token.Kind -in [TokenKind]::Identifier, [TokenKind]::Variable -or
                        $token.TokenFlags.hasFlag([TokenFlags]::Keyword)) {
                        $end = $token.Extent.EndOffset
                        $len = $end - $cursor
                        $replace = $mark + $line.SubString($cursor, $len) + $mark
                        [Microsoft.PowerShell.PSConsoleReadLine]::Replace($cursor, $len, $replace)
                        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($end + 2)
                        return
                    }
                }

                # If cursor is immediately after the end of certain tokens, enclose the token in quotes.
                # todo: move to a Ctrl+["'] key handler for cycling quote/unquote
                if ($token.Extent.StartOffset -gt $cursor - 1) {
                    $lastToken = Get-TokenFromCursorPSRL $tokens ($cursor - 1)
                    if ($lastToken -and $lastToken -ne $token) {
                        if ($lastToken.Kind -in [TokenKind]::Generic, [TokenKind]::Identifier, [TokenKind]::Variable -or
                            $lastToken.TokenFlags.hasFlag([TokenFlags]::Keyword)) {
                            $start = $lastToken.Extent.StartOffset
                            $len = $cursor - $start
                            $replace = $mark + $line.SubString($start, $len) + $mark
                            [Microsoft.PowerShell.PSConsoleReadLine]::Replace($start, $len, $replace)
                            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 2)
                            return
                        }
                    }
                }

                # Insert paired marks and move the cursor between them.
                # todo: Don't insert a pair when closing an unclosed string.
                [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$mark$mark")
                [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
                return
            }
        }

        @{
            Chord            = "Ctrl+'", 'Ctrl+"'
            BriefDescription = 'TogglePairedQuote'
            LongDescription  = 'Quotes an unquoted token, unquotes a matching-quoted token, or swaps quotes on a non-matching-quoted token.'
            ScriptBlock      = {
                param($key, $arg)

                #-- Initialization ----------------------------------------------------------------#

                $mark = $key.KeyChar
                $ast = $tokens = $parseErrors = $null
                [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$ast, [ref]$tokens, [ref]$parseErrors, [ref]$null)
                $selectionStart = $selectionLength = $null
                [Microsoft.PowerShell.PSConsoleReadLine]::GetSelectionState([ref]$selectionStart, [ref]$selectionLength)
                $line = $cursor = $null
                [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

                #-- Functions ---------------------------------------------------------------------#

                function Get-TokenFromCursorPSRL {
                    param($tokens, $cursor)
                    foreach ($token in $tokens) {
                        if ($cursor -lt $token.Extent.StartOffset) { continue }
                        if ($cursor -lt $token.Extent.EndOffset) {
                            $result = $token
                            if ($token = $token -as [StringExpandableToken]) {
                                $nested = Get-TokenFromCursorPSRL $token.NestedTokens $cursor
                                if ($nested) { $result = $nested }
                            }
                            return $result
                        }
                    }
                    return $null
                }

                function Get-TokenFromSelectionPSRL {
                    param($tokens, $start, $length)
                    $end = $start + $length
                    foreach ($token in $tokens) {
                        if ($start -lt $token.Extent.StartOffset) { continue }
                        if ($start -lt $token.Extent.EndOffset) {
                            $result = $token
                            if ($end -eq $result.Extent.EndOffset) { return $result }
                            if ($token = $token -as [StringExpandableToken]) {
                                $nested = Get-TokenFromSelectionPSRL $token.NestedTokens $start $length
                                if ($nested) { $result = $nested }
                            }
                        }
                    }
                    return $result
                }

                #######  Cycling and Toggling Quotes in Selection  ##########
                #                                                           #
                #   ## Tokens form a set of layers with depths: #########   #
                #   # +-top token-------------------------------------+ 0   #
                #   # +-token inside top------+'string inside top----'+ 1   # only strings actually "nest"
                #   # +-----------------------+'string'+'string------'+ 2   # (in token-terms, not in ast-terms)
                #                                                           #
                #   ## The "cycle" action re-quotes all strings: ########   #
                #   # +-top token-------------------------------------+ 0   #
                #   # +-token inside top------+"string inside top----"+ 1   #
                #   # +-----------------------+"string"+"string------"+ 2   #
                #                                                           #
                #   ## Then the "toggle" action either... ###############   #
                #                                                           #
                #   ## Quotes the top-most quotable-most layer: #########   #
                #   # +"string---------------------------------------"+ 0   #
                #                                                           #
                #   ## Or unquotes the top-most quoted-most layer: ######   #
                #   # +-top token-------------------------------------+ 0   #
                #   # +-token inside top------+"string inside top----"+ 1   #
                #   # +"string"+"string------"+-----------------------+ 2   #
                #   ## And further toggles ought to continue indefinitely   #
                #                                                           #
                #   ## Based on... ######################################   #
                #   # ..Whether "top token" is an exact selection #######   # > always use exact selects
                #   # ..Then, %chars quotable * ln(depth + 1) ###########   # > best layer to quote
                #   # ..Versus %chars quoted * ln(depth + 1) ############   # > best layer to unquote
                #   ## Which gives the final layer and action to take. ##   #
                #   #####################################################   #

                # function Get-TreeFromSelectionPSRL {
                #     param($tokens, $start, $length, $depth = 0, $tree = $null)
                #     $end = $start + $length
                #     $tree = $tree ?? [ordered]@{}
                #     if (!$tree.Count) { $tree += @{ 0 = @() } }
                #     foreach ($token in $tokens) {
                #         if ($start -lt $token.Extent.StartOffset) { continue }
                #         if ($end -ge $token.Extent.EndOffset) {
                #             $leaf = $token
                #             if (!$tree[$depth] -is [array]) { $tree += @{ $depth = @() } }
                #             if (Test-QuotableToken $leaf) { $tree[$depth] += $leaf }
                #             if ($leaf = $leaf -as [StringExpandableToken]) {
                #                 Get-TreeFromSelectionPSRL $leaf.NestedTokens $start $length ($depth + 1) $tree | Out-Null
                #             }
                #         }
                #     }
                #     return $tree
                # }

                # We have an elaborate criteria for what ought to have toggle-able quotation marks.
                function Test-QuotableToken {
                    param($token)
                    switch ($token.TokenFlags) {
                        { $null -eq $_ } { break }
                        {
                            $token.Kind -eq [TokenKind]::Generic -and (
                                [TokenFlags]::BinaryOperator -bor
                                [TokenFlags]::UnaryOperator -bor
                                [TokenFlags]::AssignmentOperator
                            ).hasFlag($_)
                        } { return $false }
                        { $_.hasFlag([TokenFlags]::Keyword) } { return $true }
                        { $_.hasFlag([TokenFlags]::CommandName) } { return $true }
                        { $_.hasFlag([TokenFlags]::TypeName) } { return $true }
                        { $_.hasFlag([TokenFlags]::MemberName) } { return $true }
                    }
                    switch ($token.Kind) {
                        {
                            $_ -eq [TokenKind]::Parameter -or
                            $_ -eq [TokenKind]::Generic -and
                            $token -is [StringLiteralToken] -and
                            $token.Text.StartsWith("--")
                        } { return $true }
                        { $_ -eq [TokenKind]::Comment } { return $false }
                        { $_ -eq [TokenKind]::Variable } { return $true }
                        { $_ -eq [TokenKind]::SplattedVariable } { return $true }
                        { $_ -eq [TokenKind]::StringExpandable } { return $true }
                        { $_ -eq [TokenKind]::StringLiteral } { return $true }
                        { $_ -eq [TokenKind]::HereStringExpandable } { return $true }
                        { $_ -eq [TokenKind]::HereStringLiteral } { return $true }
                        { $_ -eq [TokenKind]::Number } { return $true }
                        { $_ -eq [TokenKind]::Generic } { return $true }
                    }
                    return $false
                }

                #-- Process -----------------------------------------------------------------------#

                $other = '''"' -replace $mark, ''
                $cycleKind = $mark -eq '"' ? [StringLiteralToken] : [StringExpandableToken]
                $toggleKind = $mark -eq "'" ? [StringLiteralToken] : [StringExpandableToken]

                # Handle the case when text is selected
                if ($selectionStart -ne -1) {
                    if (!($selectionToken = Get-TokenFromSelectionPSRL $tokens $selectionStart $selectionLength)) { return }
                    if (-not (Test-QuotableToken -token $selectionToken)) { return }

                    ## Toggle quotation marks around selection
                    # (1) For token exactly enclosed by selection; if non-matching mark, cycle first; else, toggle mark.
                    # (2) Otherwise, toggle all tokens within selection; prefer "all quoted", then "none quoted".

                    if (
                        $selectionToken.Extent.StartOffset -eq $selectionStart -and
                        $selectionToken.Extent.EndOffset -eq $selectionStart + $selectionLength -or (
                            $selectionToken -is [StringToken] -and
                            $selectionToken.Value -eq $line.Substring($selectionStart, $selectionLength)
                        )
                    ) {
                        # todo: only check mark on the [StringToken] cases
                        # we do this for now to allow toggling quotes inside comments
                        # bc ?? maybe I'll want to cycle/toggle quotes in a comment one day
                        $markPattern = '\A(?<here>@)?(?<mark>[''"])?(?:.*)(?(mark)\k<mark>)(?(here)@)\z'
                        $markSelection = ''
                        if ($selectionToken.Text -match $markPattern) {
                            $markSelection = $Matches.mark
                        }

                        # Unquoted
                        if (!$markSelection) {
                            $pattern = '\A.*\z'
                            $replace = "$mark$0$mark"
                            $offset = 2
                        }
                        # Matching
                        elseif ($mark -eq $markSelection) {
                            $pattern = '\A.*\z'
                            $replace = $selectionToken.Value
                            $offset = $Matches.here ? -5 : -2
                        }
                        # Non-matching
                        else {
                            $other = $mark -eq '"' ? "'" : '"'
                            $pattern = '\A(?<here>@)?(?<mark>[''"])(?<text>.*)(\k<mark>)(?(here)@)\z'
                            $replace = '${here}' + $other + '${text}' + $other + '${here}'
                            $offset = 0
                        }

                        # Replace the exact text (not the exact selection) with cycled/toggled quotes
                        [Microsoft.PowerShell.PSConsoleReadLine]::Replace(
                            $selectionToken.Extent.StartOffset,
                            $selectionToken.Extent.EndOffset,
                            [regex]::Replace($selectionToken.Text, $pattern, $replace)
                        )
                        # todo: replace selections => new selections, not new cursor positions
                        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($selectionToken.Extent.EndOffset + $offset)
                        return
                    }

                    # todo: Loop through all tokens in selection and flip them to the next quote state
                    # ! We are just giving up and doing this, because, lol:
                    $cycleCount = $toggleCount = 0
                    foreach ($token in $tokens) {
                        if ($token -is $cycleKind) { $cycleCount++ }
                        if ($token -is $toggleKind) { $toggleCount++ }
                    }

                    if ($cycleKind -ne 0) {
                        $filter = { param($tryToken) $tryToken -is $cycleKind }
                        $pattern = '\A(?<here>@)?(?<mark>[''"])(?(here)\r?\n)(?<text>.*)(?(here)\r?\n)[''"](?(here)@)\z'
                        $replace = '${here}' + $other + '${text}' + $other + '${here}'
                    }
                    elseif ($toggleKind -ne 0) {
                        $filter = { param($tryToken) $tryToken -is $toggleKind }
                        $pattern = '\A(?<here>@)?(?<mark>[''"])(?(here)\r?\n)(?<text>.*)(?(here)\r?\n)[''"](?(here)@)\z'
                        $replace = '${text}'
                    }

                    foreach ($token in ($tokens | Where-Object $filter)) {
                        [Microsoft.PowerShell.PSConsoleReadLine]::Replace(
                            $token.Extent.StartOffset,
                            $token.Extent.EndOffset,
                            [regex]::Replace($token.Text, $pattern, $replace)
                        )
                    }
                    # todo: replace selections => new selections, not new cursor positions
                    [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($token.Extent.EndOffset)
                    return
                }

                # No text is selected; handle the typical case.
                $token = Get-TokenFromCursorPSRL $tokens $cursor

                # Handle case with cursor at start of or inside of a token.
                $pattern = $replace = $offset = $null
                if ($token -is $cycleKind) {
                    $pattern = '\A(?<here>@)?(?<mark>[''"])(?(here)\r?\n)(?<text>.*)(?(here)\r?\n)[''"](?(here)@)\z'
                    $replace = '${here}' + $other + '${text}' + $other + '${here}'
                    $offset = 0
                }
                elseif ($token -is $toggleKind) {
                    $pattern = '\A(?<here>@)?(?<mark>[''"])(?(here)\r?\n)(?<text>.*)(?(here)\r?\n)[''"](?(here)@)\z'
                    $replace = '${text}'
                    $offset = -2 # todo
                }
                elseif (Test-QuotableToken $token) {
                    $pattern = '\A|\z'
                    $replace = $mark
                    $offset = 2
                }

                if ($pattern) {
                    [Microsoft.PowerShell.PSConsoleReadLine]::Replace(
                        $token.Extent.StartOffset,
                        $token.Extent.EndOffset,
                        [regex]::Replace($token.Text, $pattern, $replace)
                    )
                    [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + $offset)
                    # Handler may need to check previous token, e.g. "string"(cursor)'string'.
                    # return
                }

                # Handle case with cursor immediately following a token.
                if ($token.Extent.StartOffset -gt $cursor - 1) {
                    if ($lastToken = Get-TokenFromCursorPSRL $tokens ($cursor - 1)) {
                        if (Test-QuotableToken $lastToken) {
                            $start = $lastToken.Extent.StartOffset
                            $len = $cursor - $start
                            $replace = $mark + $line.SubString($start, $len) + $mark
                            [Microsoft.PowerShell.PSConsoleReadLine]::Replace($start, $len, $replace)
                            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + $offset + 2)
                            return
                        }
                    }
                }
            }
        }

        @{
            Chord            = '(', '{', '['
            BriefDescription = 'InsertPairedBraces'
            LongDescription  = "Insert matching braces"
            ScriptBlock      = {
                param($key, $arg)

                # After writing all the smart quotes, I think I just wanted an easy win re: braces.
                # We do essentially nothing useful in this key handler. But it does work well.

                $closeChar = switch ($key.KeyChar) {
                    '(' { [char]')'; break }
                    '{' { [char]'}'; break }
                    '[' { [char]']'; break }
                }

                $selectionStart = $selectionLength = $null
                [Microsoft.PowerShell.PSConsoleReadLine]::GetSelectionState([ref]$selectionStart, [ref]$selectionLength)

                $line = $cursor = $null
                [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

                # Handle case when text is selected.
                if ($selectionStart -ne - 1) {
                    $replace = $key.KeyChar + $line.SubString($selectionStart, $selectionLength) + $closeChar
                    [Microsoft.PowerShell.PSConsoleReadLine]::Replace($selectionStart, $selectionLength, $replace)
                    [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($selectionStart + $replace.Length)
                    return
                }

                # Insert paired braces.
                [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$($key.KeyChar)$closeChar")
                [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
                return
            }
        }

        @{
            Chord            = ')', ']', '}'
            BriefDescription = 'SmartCloseBraces'
            LongDescription  = "Insert closing brace or skip over closing brace"
            ScriptBlock      = {
                param($key, $arg)

                $line = $cursor = $null
                [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

                # Our "smarts" are to move over a closing brace without checking it closes anything.
                if ($line[$cursor] -eq $key.KeyChar) {
                    [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
                    return
                }

                # Otherwise, we have nothing to be smart about.
                [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$($key.KeyChar)")
            }
        }

        @{
            Chord            = "Ctrl+."
            BriefDescription = 'ResolveCommandAliases'
            LongDescription  = "Resolve all (built-in) aliases to their full command."
            ScriptBlock      = {
                $ast = $tokens = $errors = $cursor = $null
                [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$ast, [ref]$tokens, [ref]$errors, [ref]$cursor)

                $startAdjustment = 0
                foreach ($token in $tokens) {
                    if ($token.TokenFlags -band [TokenFlags]::CommandName) {
                        if ($alias = $ExecutionContext.InvokeCommand.GetCommand($token.Extent.Text, 'Alias')) {
                            if ($resolvedCommand = $alias.ResolvedCommandName) {
                                $extent = $token.Extent
                                $length = $extent.EndOffset - $extent.StartOffset
                                [Microsoft.PowerShell.PSConsoleReadLine]::Replace(
                                    $extent.StartOffset + $startAdjustment,
                                    $length,
                                    $resolvedCommand
                                )
                                $startAdjustment += ($resolvedCommand.Length - $length)
                            }
                        }
                    }
                }
                return
            }
        }
    )

    SmartMultiline    = @(
        @{
            Chord            = 'Enter'
            BriefDescription = 'EnterSmartMultiline'
            LongDescription  = 'Inserts a newline or validates and runs the current command.'
            ScriptBlock      = {
                $line = $cursor = $null;
                [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
                $ast = $tokens = $errors = $cursor = $null
                [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$ast, [ref]$tokens, [ref]$errors, [ref]$cursor)

                # If the buffer contains only newlines, [Enter] expands the vertical space by 1 line.
                if ($line -match '\A[\r\n]*\z') {
                    if ($line.Length -lt ($env:WT_MAX_NEWLINE ?? 10)) {
                        [Microsoft.PowerShell.PSConsoleReadLine]::InsertLineBelow();
                    }
                    # Center the cursor vertically in the space, biased downward.
                    [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition([Math]::Floor(($line.Length + 1) / 2));
                    return
                }

                # Commands preceded with 2 spaces (ex.) are hidden from the command history.
                if ($line -match '\A[ ]{2}(?=\S)' -and $line -notmatch '\bSkip-History(\b|$)') {
                    <# 'Skip-History' is not a default pwsh command, so we check that it exists. #>
                    if (Get-Command -Name 'Skip-History') {
                        $canSkipIntent = $false, [Microsoft.PowerShell.AddToHistoryOption]::SkipAdding
                        $handlerIntent = (Get-PSReadLineOption).AddToHistoryHandler.DynamicInvoke($line)
                        $intentWillAdd = $handlerIntent -in $canSkipIntent
                        if ($intentWillAdd) {
                            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($line.Length);
                            [Microsoft.PowerShell.PSConsoleReadLine]::Insert(' | Skip-History');
                        }
                    }

                    # Validate commands containing secrets -- further prevents propagating sensitive data via error logs.
                    [Microsoft.PowerShell.PSConsoleReadLine]::ValidateAndAcceptLine();
                    return
                }

                # Handle case when cursor is at the start of a command.
                if ($cursor -eq 0 -and $line.Length -gt 0) {
                    [Microsoft.PowerShell.PSConsoleReadLine]::ValidateAndAcceptLine();
                    return
                }

                # Handle herestrings/docstrings. Enter acts like Shift+Enter inside of them.
                #? Do they act as "incomplete" in parseErrors? I didn't think so when writing this.
                if (
                    $cursor -notin (0, 1, $line.Length) -and
                    $line.Substring($cursor - 2, 3) -match '^@(?<mark>["''])(\k<mark>)$'
                ) {
                    if ($line[$cursor + 1] -ne '@') {
                        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
                        [Microsoft.PowerShell.PSConsoleReadLine]::Insert("@")
                        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor)
                    }
                    [Microsoft.PowerShell.PSConsoleReadLine]::Insert("`n`n")
                    [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
                    return
                }

                # Handle when the parsed command is incomplete, e.g. a brace etc. is unclosed:
                # [Enter] then acts like [Shift]+[Enter], but maybe with lopsided indentation.
                # todo: just parse things; contexts like this are unnecessary.
                if ($errors | Where-Object IncompleteInput) {
                    # Handle inserting a newline in the given context.
                    $tab_length = [int] $env:WT_TAB_SPACES ?? 4
                    $max_nesting = [int] $env:WT_MAX_NESTING ?? 20

                    <# @{ [int]length = [string[]] } #>
                    $increaseAfter = @{
                        1 = '(', '[', '{'
                        2 = '@"', "@'"
                    }
                    $increaseBefore = @{}
                    $decreaseAfter = @{}
                    $decreaseBefore = @{
                        1 = ')', ']', '}'
                    }
                    $resetAfter = @{
                        2 = '@"', "@'"
                    }
                    $resetBefore = @{
                        2 = '"@', "'@"
                    }
                    # todo: bump pipelines one level, but only one level, not stacking? non-standard
                    $increaseAfterOnce = @{
                        1 = '|'
                        2 = '||', "&&"
                    }
                    $increaseBeforeOnce = @{}

                    function Test-CursorBetweenContexts ($line, $cursor, $after_context, $before_context) {
                        $keys = $after_context.Keys + $before_context.Keys | Select-Object -Unique
                        foreach ($key in $keys) {
                            if ($after_context) {
                                if (
                                    $line.Length -ge $key -and
                                    $cursor -ge $key -and
                                    $line.SubString($cursor - $key, $key) -in $after_context[$key]
                                ) { return $true }
                            }
                            if ($before_context) {
                                if (
                                    $line.Length -ge $key + $cursor -and
                                    $line.SubString($cursor, $key) -in $before_context[$key]
                                ) { return $true }
                            }
                        }
                        return $false
                    }

                    # Check the surrounding context

                    # Reset indentation
                    if (Test-CursorBetweenContexts $line $cursor $resetAfter $resetBefore) {
                        [Microsoft.PowerShell.PSConsoleReadLine]::Insert("`n`n")
                        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
                        return
                    }

                    # Update indentation
                    $line_current = ($line.Substring(0, $cursor) -split '\n')[-1]
                    $indentation = $line_current -match "^(?<indent>(?:\s{$tab_length})+)" ? $Matches.indent : ''
                    $nesting = $indentation.length / $tab_length

                    $expansion = "`n"
                    $position = $cursor + $expansion.Length

                    # Increase indentation
                    if (
                        $nesting -lt $max_nesting -and
                            (Test-CursorBetweenContexts $line $cursor $increaseAfter $increaseBefore)
                    ) {
                        $expansion += ' ' * $tab_length * ($nesting + 1)
                        $position = $cursor + $expansion.Length

                        # Then, also decrease indentation:
                        if ((Test-CursorBetweenContexts $line $cursor $decreaseAfter $decreaseBefore)) {
                            $expansion += "`n"
                            $expansion += ' ' * ($tab_length * $nesting)
                        }
                    }
                    # Decrease indentation:
                    elseif (
                        $nesting -ge 1 -and
                            (Test-CursorBetweenContexts $line $cursor $decreaseAfter $decreaseBefore)
                    ) {
                        $expansion += "`n"
                        $expansion += ' ' * $tab_length * ($nesting - 1)
                        $position += $expansion.Length
                    }
                    # Hold indentation:
                    else {
                        $expansion += ' ' * ($tab_length * $nesting)
                        $position += $tab_length * $nesting
                    }
                    [Microsoft.PowerShell.PSConsoleReadLine]::Insert($expansion)
                    [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($position)
                    return
                }

                # Handle execution of command

                # Expression in the buffer is balanced -- Enter acts as trim + accept command.
                # Non-builtin aliases cause this validation to fail; these can be run with Ctrl+Shift+Enter.
                $replace = $line -replace '\A\s*|\s*\z', '';
                [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine(); # Revert does not add to Undo stack.
                [Microsoft.PowerShell.PSConsoleReadLine]::Insert($replace);
                [Microsoft.PowerShell.PSConsoleReadLine]::ValidateAndAcceptLine();
            }
        }

        @{
            Chord            = 'Shift+Enter'
            BriefDescription = 'InsertMultilineBelow'
            LongDescription  = 'Insert a new line _below_ and move the cursor to the same indentation.'
            ScriptBlock      = {
                $line = $cursor = $null;
                [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref] $line, [ref] $cursor);

                #todo: support selections.

                #-- Functions ---------------------------------------------------------------------#

                function Test-CursorBetweenContexts ($line, $cursor, $after_context, $before_context) {
                    $keys = $after_context.Keys + $before_context.Keys | Select-Object -Unique
                    foreach ($key in $keys) {
                        if ($after_context) {
                            if (
                                $line.Length -ge $key -and
                                $cursor -ge $key -and
                                $line.SubString($cursor - $key, $key) -in $after_context[$key]
                            ) { return $true }
                        }
                        if ($before_context) {
                            if (
                                $line.Length -ge $key + $cursor -and
                                $line.SubString($cursor, $key) -in $before_context[$key]
                            ) { return $true }
                        }
                    }
                    return $false
                }

                #-- Process -----------------------------------------------------------------------#

                # Handle the empty command line.
                if (!$line.Length -or $cursor -eq 0) {
                    [Microsoft.PowerShell.PSConsoleReadLine]::InsertLineBelow()
                    [Microsoft.PowerShell.PSConsoleReadLine]::MoveToEndOfLine()
                    return
                }

                # Handle herestrings/heredocs.
                if (
                    $cursor -notin (0, 1, $line.Length) -and
                    $line.Substring($cursor - 2, 3) -match '^@(?<mark>["''])(\k<mark>)$'
                ) {
                    if ($line[$cursor + 1] -ne '@') {
                        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
                        [Microsoft.PowerShell.PSConsoleReadLine]::Insert("@")
                        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor)
                    }
                    [Microsoft.PowerShell.PSConsoleReadLine]::Insert("`n`n")
                    [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
                    return
                }

                # Handle various contexts (left/right bounds) where newlines modify indentation.
                # Each "context" is a hashtable: @{ [int]length = [string[]]bounds }.
                # Bounds are paired into before/after by their position in the array.

                $tab_length = [int] $env:WT_TAB_SPACES ?? 4
                $max_nesting = [int] $env:WT_MAX_NESTING ?? 20

                $increaseAfter = @{
                    1 = '(', '[', '{'
                    2 = '@"', "@'"
                }
                $increaseBefore = @{} <# does this exist? #>
                $decreaseAfter = @{}  <# does this exist? #>
                $decreaseBefore = @{
                    1 = ')', ']', '}'
                }
                $resetAfter = @{
                    2 = '@"', "@'"
                }
                $resetBefore = @{
                    2 = '"@', "'@"
                }

                # todo: bump pipelines one level, but only one level, not stacking
                # todo: this requires actually parsing the command in the buffer
                $increaseAfterOnce = @{
                    1 = '|'
                    2 = '||', "&&"
                }
                $increaseBeforeOnce = @{}

                # Reset indentation
                if (Test-CursorBetweenContexts $line $cursor $resetAfter $resetBefore) {
                    [Microsoft.PowerShell.PSConsoleReadLine]::Insert("`n`n")
                    [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
                    return
                }

                # Increase/decrease/hold indentation
                $line_current = ($line.Substring(0, $cursor) -split '\n')[-1]
                $indentation = $line_current -match "^(?<indent>(?:\s{$tab_length})+)" ? $Matches.indent : ''
                $nesting = $indentation.length / $tab_length

                $expansion = "`n"
                $position = $cursor + $expansion.Length

                # Increase indentation
                if (
                    $nesting -lt $max_nesting -and
                    $(Test-CursorBetweenContexts $line $cursor $increaseAfter $increaseBefore)
                ) {
                    $expansion += ' ' * $tab_length * ($nesting + 1)
                    $position = $cursor + $expansion.Length

                    # After an increase, we may need to decrease indentation on the next line, also:
                    if ((Test-CursorBetweenContexts $line $cursor $decreaseAfter $decreaseBefore)) {
                        $expansion += "`n"
                        $expansion += ' ' * ($tab_length * $nesting)
                    }
                }
                # Decrease indentation:
                elseif (
                    $nesting -ge 1 -and
                    $(Test-CursorBetweenContexts $line $cursor $decreaseAfter $decreaseBefore)
                ) {
                    $expansion += "`n"
                    $expansion += ' ' * $tab_length * ($nesting - 1)
                    $position += $expansion.Length
                }
                # Hold indentation:
                else {
                    $expansion += ' ' * ($tab_length * $nesting)
                    $position += $tab_length * $nesting
                }

                [Microsoft.PowerShell.PSConsoleReadLine]::Insert($expansion)
                [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($position)
            }
        }

        @{
            Chord            = 'Ctrl+Enter'
            BriefDescription = 'InsertMultilineAbove'
            LongDescription  = 'Insert a new line _above_ and move the cursor to the same indentation.'
            ScriptBlock      = {
                $line = $cursor = $null;
                [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref] $line, [ref] $cursor);
                $tab_length = $env:WT_TAB_SPACES ?? 4
                
                $line_current = $line.Substring(0, $cursor) -split '\n' | Select-Object -Last 1
                $indentation = $line_current -match "^(?<indent>(?:\s{$tab_length})+)" ? $Matches.indent : '';
                [Microsoft.PowerShell.PSConsoleReadLine]::BeginningOfLine();
                [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$indentation`n");
                [Microsoft.PowerShell.PSConsoleReadLine]::BackwardChar();
            }
        }

        @{
            Chord            = 'Ctrl+Shift+Enter'
            BriefDescription = 'ForceAcceptCommand'
            LongDescription  = 'Run the command with no validation (e.g., without resolving aliases). Can do strange things.'
            ScriptBlock      = {
                $line = $cursor = $null;
                [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref] $line, [ref] $cursor);

                # Commands preceded with 2 spaces (ex.) are hidden from the command history.
                if ($line -match '\A[ ]{2}(?=\S)' -and $line -notmatch '\bSkip-History(\b|$)') {
                    <# 'Skip-History' is not a default pwsh command, so we check that it exists. #>
                    if (Get-Command -Name 'Skip-History') {
                        $canSkipIntent = $false, [Microsoft.PowerShell.AddToHistoryOption]::SkipAdding
                        $handlerIntent = (Get-PSReadLineOption).AddToHistoryHandler.DynamicInvoke($line)
                        $intentWillAdd = $handlerIntent -in $canSkipIntent
                        if ($intentWillAdd) {
                            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($line.Length);
                            [Microsoft.PowerShell.PSConsoleReadLine]::Insert(' | Skip-History');
                        }
                    }

                    # Validate commands containing secrets -- further prevents propagating sensitive data via error logs.
                    [Microsoft.PowerShell.PSConsoleReadLine]::ValidateAndAcceptLine();
                    return
                }

                # Trim and reformat command.
                $replace = $line -replace '\A\s*|\s*\z', '';
                [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine();
                [Microsoft.PowerShell.PSConsoleReadLine]::Insert($replace);

                # As opposed to ValidateAndAcceptLine:
                [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine();
            }
        }

        @{
            Chord            = 'Backspace'
            BriefDescription = 'BackspaceSmartMultiline'
            LongDescription  = 'Deletes either the previous character or a trailing newline.'
            ScriptBlock      = {
                $line = $cursor = $null;
                [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref] $line, [ref] $cursor)
                $selectionStart = $selectionLength = $null
                [Microsoft.PowerShell.PSConsoleReadLine]::GetSelectionState([ref]$selectionStart, [ref]$selectionLength)

                if (!$line) { return }

                # With the cursor in the first position, empty the buffer on a double-backspace.
                if ($cursor -eq 0 -and $selectionStart -eq -1) {
                    $duration = New-TimeSpan -Milliseconds 200
                    $pressTime = Get-Date;
                    if ($DoubleBackspaceReady -and $pressTime - $DoubleBackspaceTime -le $duration) {
                        $global:DoubleBackspaceReady = $false
                        $global:DoubleBackspaceTime = $pressTime
                        # Use Replace instead of Revert to create an Undo entry.
                        [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $line.Length, '')
                        return
                    }
                    $global:DoubleBackspaceReady = $true
                    $global:DoubleBackspaceTime = $pressTime
                    return
                }

                # Handle selections.
                if ($selectionStart -ne -1) {
                    [Microsoft.PowerShell.PSConsoleReadLine]::Replace(
                        $selectionStart,
                        $selectionLength,
                        ''
                    )
                    [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($selectionStart)
                    return
                }

                # Detect paired characters around the cursor.
                $toMatch = switch ($line[$cursor]) {
                    '"' { '"'; break }
                    "'" { "'"; break }
                    ')' { '('; break }
                    ']' { '['; break }
                    '}' { '{'; break }
                    default { $null }
                }

                # Remove both characters of any matching pairs. #todo: matching paired tokens.
                if ($toMatch -and $line[$cursor - 1] -eq $toMatch) {
                    [Microsoft.PowerShell.PSConsoleReadLine]::Delete($cursor - 1, 2)
                    return
                }

                # Vertical editing: When backspace-ing through newlines, recenter the cursor vertically.
                if ($line -match '\A[\r\n]+\z') {
                    [Microsoft.PowerShell.PSConsoleReadLine]::BackwardDeleteChar();
                    [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition([Math]::Floor(($line.Length - 1) / 2));
                    return
                }

                # Nothing left to be smart about.
                [Microsoft.PowerShell.PSConsoleReadLine]::BackwardDeleteChar();
            }
        }
    )
}
