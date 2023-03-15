# You can add this CurrentUserAllHosts file to your profile for some extra text handling while in the console.
# This partial profile is focused on giving a consistent cli dx between vscode and win terminal.

# It features mostly key handling, including:
# (1) Command validation. Checks for mistyped commands, mismatched parens, incorrect operators, etc.
# (2) Auto-balancing. Inserts paired quotes and braces, moves cursor to unbalanced positions in expressions.
# (3) Vertical expansion. Hitting Enter repeatedly adds new lines, like Shift+Enter. I like visual space.
# (4) Command trimming. Extra vertical space is removed when running commands. I don't like pointless pad.
# (5) "Buried" commands. Follows practice of two spaces before a command being hidden from history.


# # PROMPT

. 'C:\Users\efrec\Documents\VSCode\admin\profile\prompt.ps1'
Set-PSReadLineOption -ContinuationPrompt '< ' # inverse of '> '


# # KEY HANDLING

#* General replacements
# Remove Terminal's Ctrl+Shift+V (it does a normal Paste - incomprehensibly vile) and use this:
#! Problem: Insert() adds ctrl+m command characters at some (not all?) line endings. Need to know the rule to change the behavior.
Set-PSReadLineKeyHandler -Chord Ctrl+Shift+V `
    -BriefDescription PasteValuesAsInsert `
    -Description 'Pastes from the clipboard without screwing it up horrifically (as is default)' `
    -ScriptBlock {
    $values = (Get-Clipboard -Text) -join '\n'
    [Microsoft.PowerShell.PSConsoleReadLine]::Insert($values)
}

#* Smart insertion and deletion, especially for matching pairs.
# Also includes a Ctrl+. chord to replace aliases with their resolved commands.
# todo: Ctrl+["'] for cycling unquote/cycle quote type

# todo: detect, insert, expand herestrings
Set-PSReadLineKeyHandler -Chord '"', "'" `
    -BriefDescription InsertPairedQuote `
    -Description 'Insert paired quotes if not already inside a quoted string. Swap single/double quotes with a string selected.' `
    -ScriptBlock {
    param($key, $arg)
    $mark = $key.KeyChar

    $selectionStart = $selectionLength = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetSelectionState([ref]$selectionStart, [ref]$selectionLength)
    $line = $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
    
    # If text is selected, just quote it without any smarts.
    # We're still smart enough to replace start/end quotation pairs when at extents of highlight region.
    # todo: detect if selection is forward or backward and move cursor to the correct side
    if ($selectionStart -ne -1) {
        # todo: Regex should be replaced with tokenized input; see later example for token logic.
        [Microsoft.PowerShell.PSConsoleReadLine]::Replace(
            $selectionStart,
            $selectionLength,
            $mark + [regex]::Replace($line.SubString($selectionStart, $selectionLength), "\A(['`"])(.*)(\1)\z", '$2') + $mark
        )
        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($selectionStart + $selectionLength + 2)
        return
    }

    $ast = $null
    $tokens = $null
    $parseErrors = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$ast, [ref]$tokens, [ref]$parseErrors, [ref]$null)

    function FindToken {
        param($tokens, $cursor)
        foreach ($token in $tokens) {
            if ($cursor -lt $token.Extent.StartOffset) { continue }
            if ($cursor -lt $token.Extent.EndOffset) {
                $result = $token
                $token = $token -as [StringExpandableToken] # for get_NestedTokens
                if ($token) {
                    $nested = FindToken $token.NestedTokens $cursor
                    if ($nested) { $result = $nested }
                }
                return $result
            }
        }
        return $null
    }

    $token = FindToken $tokens $cursor

    # If we're on or inside a *quoted* string token (so not generic), we need to be smarter
    if ($token -is [StringToken] -and $token.Kind -ne [TokenKind]::Generic) {
        # If we're at the start of the string, assume we're inserting a new string
        if ($token.Extent.StartOffset -eq $cursor) {
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$mark")
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$mark ") # separate undo entry lets us ctrl+z this
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1) # between the new marks
            return
        }
        # If we're at the end of the string, move over the closing quote if present.
        if ($token.Extent.EndOffset -eq ($cursor + 1) -and $line[$cursor] -eq $mark) {
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
            return
        }
    }

    if ($null -eq $token -or
        $token.Kind -in [TokenKind]::RParen, [TokenKind]::RCurly, [TokenKind]::RBracket) {
        # ! Disregards escaped and commented quotation marks
        if ($line[0..$cursor].Where{ $_ -eq $mark }.Count % 2 -eq 1) {
            # Odd number of quotes before the cursor, insert a single quote
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($mark)
        }
        else {
            # Insert matching quotes, move cursor to be in between the quotes
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$mark$mark")
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
        }
        return
    }

    # If cursor is at the start of a token, enclose it in quotes.
    # todo: move to Ctrl+["'] key handler for cycling quote/unquote
    if ($token.Extent.StartOffset -eq $cursor) {
        if ($token.Kind -in [TokenKind]::Generic, [TokenKind]::Identifier, [TokenKind]::Variable -or
            $token.TokenFlags.hasFlag([TokenFlags]::Keyword)) {
            $end = $token.Extent.EndOffset
            $len = $end - $cursor
            [Microsoft.PowerShell.PSConsoleReadLine]::Replace($cursor, $len, $mark + $line.SubString($cursor, $len) + $mark)
            # [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($end + 2)
            return
        }
    }
    # If cursor is immediately after the end of a token, enclose the token in quotes.
    # todo
    else {
        $token = FindToken $tokens ($cursor - 1)
        write-host $token.Text
        if ($token -and $token.Extent.EndOffset -eq $cursor - 1) {
            if ($token.Kind -in [TokenKind]::Generic, [TokenKind]::Identifier, [TokenKind]::Variable -or
                $token.TokenFlags.hasFlag([TokenFlags]::Keyword)) {
                $start = $token.Extent.StartOffset
                $len = $cursor - $start
                [Microsoft.PowerShell.PSConsoleReadLine]::Replace($start, $len, $mark + $line.SubString($start, $len) + $mark)
                [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 2)
                return
            }
        }
    }

    # We failed to be smart, so just insert a single quote
    [Microsoft.PowerShell.PSConsoleReadLine]::Insert($mark)
}

Set-PSReadLineKeyHandler -Key '(', '{', '[' `
    -BriefDescription InsertPairedBraces `
    -LongDescription "Insert matching braces" `
    -ScriptBlock {
    param($key, $arg)

    $closeChar = switch ($key.KeyChar) {
        <#case#> '(' { [char]')'; break }
        <#case#> '{' { [char]'}'; break }
        <#case#> '[' { [char]']'; break }
    }

    $selectionStart = $selectionLength = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetSelectionState([ref]$selectionStart, [ref]$selectionLength)

    $line = $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
    
    if ($selectionStart -ne -1) {
        # Text is selected, wrap it in brackets
        [Microsoft.PowerShell.PSConsoleReadLine]::Replace($selectionStart, $selectionLength, $key.KeyChar + $line.SubString($selectionStart, $selectionLength) + $closeChar)
        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($selectionStart + $selectionLength + 2)
    }
    else {
        # No text is selected, insert a pair
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$($key.KeyChar)$closeChar")
        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
    }
}

Set-PSReadLineKeyHandler -Key ')', ']', '}' `
    -BriefDescription SmartCloseBraces `
    -LongDescription "Insert closing brace or skip over closing brace" `
    -ScriptBlock {
    param($key, $arg)

    $line = $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

    if ($line[$cursor] -eq $key.KeyChar) {
        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
    }
    else {
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$($key.KeyChar)")
    }
}

# todo: resolve parameter aliases
Set-PSReadLineKeyHandler -Key "Ctrl+." `
    -BriefDescription ResolveCommandAliases `
    -LongDescription "Resolve all aliases to their full command. Only works for builtin aliases." `
    -ScriptBlock {
    $ast = $null
    $tokens = $null
    $errors = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$ast, [ref]$tokens, [ref]$errors, [ref]$cursor)

    $startAdjustment = 0
    foreach ($token in $tokens) {
        if ($token.TokenFlags -band [TokenFlags]::CommandName) {
            $alias = $ExecutionContext.InvokeCommand.GetCommand($token.Extent.Text, 'Alias')
            if ($alias -ne $null) {
                $resolvedCommand = $alias.ResolvedCommandName
                if ($resolvedCommand -ne $null) {
                    $extent = $token.Extent
                    $length = $extent.EndOffset - $extent.StartOffset
                    [Microsoft.PowerShell.PSConsoleReadLine]::Replace(
                        $extent.StartOffset + $startAdjustment,
                        $length,
                        $resolvedCommand)

                    # Our copy of the tokens won't have been updated, so we need to
                    # adjust by the difference in length
                    $startAdjustment += ($resolvedCommand.Length - $length)
                }
            }
        }
    }
}

#* Multiline editing mode. More modern-feeling, but not quite vim. Trying for the sweet spot.

# We have to check for balanced parenthesis, brackets, and braces.
# This script takes care of that for us w/ a simple stack (fooled v. easily).
# todo: no reason for this to be in csharp instead of a pwsh class; just makes editing this annoying.
# todo: after figuring out tokens, this is a pretty ridiculous approach; change over to token logic.
Add-Type -Language CSharp -TypeDefinition @"
using System;
using System.Collections.Generic;

public class BalancedBrackets {
    public enum Balancing : int
    {
        BalancedBrackets = 0,
        MissingOpenBracket = 1,
        MissingCloseBracket = 2
    }

    private class Stack {
        public int top = -1;
        public char[] items = new char[127];
        public void push(char x)
        {
            if (top == 126)
            {
                Console.WriteLine("Stack full");
            }
            else {
                items[++top] = x;
            }
        }
        char pop()
        {
            if (top == -1)
            {
                Console.WriteLine("Underflow error");
                return '�';
            }
            else
            {
                char element = items[top];
                top--;
                return element;
            }
        }
        bool isEmpty()
        {
            return (top == -1) ? true : false;
        }
    }

    public static bool isMatchingPair(char character1, char character2)
    {
        if (character1 == '(' && character2 == ')')
            return true;
        else if (character1 == '{' && character2 == '}')
            return true;
        else if (character1 == '[' && character2 == ']')
            return true;
        else
            return false;
    }

    public static bool isBalancedExpression(char[] exp)
    {
        // Declare an empty character stack
        Stack<char> st = new Stack<char>();
        // Traverse the given expression to check matching brackets
        for (int i = 0; i < exp.Length; i++)
        {
            // open punctuation adds to the stack
            if (exp[i] == '{' || exp[i] == '(' || exp[i] == '[')
                st.Push(exp[i]);
            // and closing punctuation removes from the stack
            if (exp[i] == '}' || exp[i] == ')' || exp[i] == ']') {
                if (st.Count == 0)
                {
                    return false;
                }
                else if (!isMatchingPair(st.Pop(), exp[i])) {
                    return false;
                }
            }
        }
        // If something is left in the expression, there are too many open brackets
        if (st.Count == 0)
            return true;
        else
        {
            return false;
        }
    }

    public static bool isMissingOpenBracket(char[] exp)
    {
        Stack<char> st = new Stack<char>();
        for (int i = 0; i < exp.Length; i++)
        {
            if (exp[i] == '{' || exp[i] == '(' || exp[i] == '[')
                st.Push(exp[i]);
            if (exp[i] == '}' || exp[i] == ')' || exp[i] == ']') {
                if (st.Count == 0)
                {
                    return true;
                }
                else if (!isMatchingPair(st.Pop(), exp[i])) {
                    return false;
                }
            }
        }
        return false;
    }

    public static int testExpression(char[] exp)
    {
        Stack<char> st = new Stack<char>();
        for (int i = 0; i < exp.Length; i++)
        {
            if (exp[i] == '{' || exp[i] == '(' || exp[i] == '[')
                st.Push(exp[i]);
            if (exp[i] == '}' || exp[i] == ')' || exp[i] == ']') {
                if (st.Count == 0)
                {
                    return (int)Balancing.MissingOpenBracket;
                }
                else if (!isMatchingPair(st.Pop(), exp[i])) {
                    return (int)Balancing.MissingOpenBracket;
                }
            }
        }
        if (st.Count == 0)
            return (int)Balancing.BalancedBrackets;
        else
        {
            return (int)Balancing.MissingCloseBracket;
        }
    }
}
"@

# Enter key expands the space in the prompt/buffer semi-intelligently. I call this "multiline" mode.
# The cursor automatically centers within the vertical space to give padding while editing. OCD thing.
# Enter also runs commands, the typical way, when the expression is a complete command.
# todo: rewrite w/ tokens as appropriate; avoid doing your own string processing.
Set-PSReadLineKeyHandler -Chord Enter `
    -BriefDescription EnterMultiline `
    -Description 'Insert a newline or validate and run the current command' `
    -ScriptBlock {
    # Get the current contents of the prompt.
    $line = $cursor = $null;
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref] $line, [ref] $cursor);

    if ($line -match '\A[\r\n]*\z') {
        # Buffer state is empty except for newlines
        # Add another newline, then recenter in the buffer; cursor position is biased upwards.
        [Microsoft.PowerShell.PSConsoleReadLine]::InsertLineBelow();
        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition([Math]::Floor(($line.Length + 1) / 2));
    }
    elseif ($line -match '\A[ ]{2}\S') {
        # Command is preceded by exactly two spaces
        # todo: "Bury" command, hiding it from command history
        # todo: Also do not perform command validation; this is to keep secrets out of error history, logs, etc.
        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine();
    }
    else {
        # ! Disregards escaped and commented-out brackets. __Use tokens.__
        switch ([BalancedBrackets]::testExpression($line)) {
            1 {
                # Missing at least one open bracket
                # -- Display an error and move cursor to "mismatch" location (it tries)
                [Microsoft.PowerShell.PSConsoleReadLine]::ValidateAndAcceptLine();
                break
            }
            2 {
                # Missing at least one close bracket
                # -- Assume the user is still typing out the command
                # -- Maintain, increase, or decrease the indent level as appropriate
                $line_current = ($line.Substring(0, $cursor) -split '\n')[-1]
                $indentation = $line_current -match '^(?<indent>\s*)' ? $Matches.indent : ''
                $indentation = "`n$indentation"
                if ($line[$cursor - 1] -in '(', '[', '{') {
                    $indentation += (' ' * 2)
                }
                # todo: missing cases where indentation may need to increase
                # todo: missing guards where indentation should not decrease
                # todo: missing cases where indentation should decrease
                # todo: realign close brackets to indentation level of matching open brackets
                elseif ($line[$cursor - 1] -in ')', ']', '}') {
                    $indentation = $indentation.Substring(2)
                }
                [Microsoft.PowerShell.PSConsoleReadLine]::Insert($indentation);
                break
            }
            default {
                # Expression is probably balanced; may have escaped/commented/string brackets.
                # We test for remaining alternative expansions, otherwise running the normal Enter command.

                if (
                    $cursor -notin (0, $line.Length) -and
                    $line.Substring($cursor - 1, 2) -in '()', '[]', '{}' -and
                    -not (
                        $line.Substring($cursor - 1, 2) -eq '[]' -and
                        $line.SubString(0, $cursor) -match '\A(\s*|#[^\n]*(?=\n))\[\]' # why am I guarding comments/whitespace?
                    )
                ) {
                    # Cursor is directly between two brackets, which are not following all-whitespace, nor in a comment.
                    # Expand between the brackets with newlines and proper indentation.
                    $line_current = ($line.Substring(0, $cursor) -split '\n')[-1]
                    $indentation = $line_current -match '^(?<indent>\s*)' ? $Matches.indent : ''
                    [Microsoft.PowerShell.PSConsoleReadLine]::Insert("`n$indentation  `n$indentation");
                    [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + $indentation.Length + 3);
                    return;
                }
                
                if (
                    $cursor -notin (0, 1, $line.Length) -and
                    $line.Substring($cursor - 2, 3) -in '@""', "@''"
                ) {
                    # We are in a new here-string, which may or may not be closed already.
                    # Check that the herestring gets closed properly (with "@ or '@).
                    # Then, insert two newlines between the quotation marks.
                    if ($close_here = $line.Substring($cursor) -match "\A['`"]@" ? '' : '@') {
                        # Herestring is missing its closing mark
                        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1);
                        [Microsoft.PowerShell.PSConsoleReadLine]::Insert($close_here);
                        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor);
                    }
                    [Microsoft.PowerShell.PSConsoleReadLine]::Insert("`n`n");
                    [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1);
                    return;
                }

                # Trim and validate command; command runs if it passes validation.
                # Non-builtin aliases cause this validation to fail, but can be run with Ctrl+Shift+Enter.
                $replace = $line -replace '\A\s*|\s*\z', '';
                [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine(); # does not add to Undo stack
                [Microsoft.PowerShell.PSConsoleReadLine]::Insert($replace);
                [Microsoft.PowerShell.PSConsoleReadLine]::ValidateAndAcceptLine();
            }
        }
    }
}

# Add indentation support for Shift-Enter (AddLine) and Ctrl+Enter (InsertLineAbove)
Set-PSReadLineKeyHandler -Chord Shift+Enter `
    -BriefDescription InsertMultiline `
    -Description 'Move the cursor to a new line at the same indentation, without executing input.' `
    -ScriptBlock {
    $line = $cursor = $null;
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref] $line, [ref] $cursor);

    $line_current = ($line.Substring(0, $cursor) -split '\n')[-1]
    $indentation = $line_current -match '^(?<indent>\s*)' ? $Matches.indent : ''
    [Microsoft.PowerShell.PSConsoleReadLine]::Insert("`n$indentation");
    [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + $indentation.Length + 1);
}
Set-PSReadLineKeyHandler -Chord Ctrl+Enter `
    -BriefDescription InsertMultilineAbove `
    -Description 'Insert a new line above and move the cursor to the same indentation, without executing input.' `
    -ScriptBlock {
    $line = $cursor = $null;
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref] $line, [ref] $cursor);

    $line_current = ($line.Substring(0, $cursor) -split '\n')[-1]
    $indentation = $line_current -match '^(?<indent>\s*)' ? $Matches.indent : ''
    [Microsoft.PowerShell.PSConsoleReadLine]::BeginningOfLine();
    [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$indentation`n");
    [Microsoft.PowerShell.PSConsoleReadLine]::BackwardChar();
    # [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + $indentation.Length + 1);
}

# The Enter key won't run a command which does not validate—but readline does not validate *aliases*.
# I agree with that. So allow the override here, to keep from having to rewrite valid, aliased commands.
# You can also run empty commands, etc., this way.
Set-PSReadLineKeyHandler -Chord Ctrl+Shift+Enter `
    -BriefDescription AcceptCommand `
    -Description 'Run command without validation (e.g. with alias)' `
    -ScriptBlock {
    $line = $cursor = $null;
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref] $line, [ref] $cursor);
    if ($line -notmatch '\A[ ]{2}\S') {
        # todo: bury commands preceded by two spaces
        $replace = $line -replace '\A\s*|\s*\z', '';
        [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine();
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert($replace);
    }
    [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
}

# Backspace clears trailing newlines to keep a typewriter-style presentation w/ vertically centered text.
# The (odd) purpose here is to give myself vertical space to "think". I am just this way.
Set-PSReadLineKeyHandler -Chord Backspace `
    -BriefDescription BackspaceMultiline `
    -Description 'Delete previous character or trailing newline' `
    -ScriptBlock {
    $line = $cursor = $null;
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref] $line, [ref] $cursor);

    # Clear a final dangling newline so that Backspace can act like Delete in this one case
    if ([string]$line -eq "`n") {
        [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine();
        return
    }

    # Delete matching braces
    if ($cursor -gt 0) {
        $toMatch = $null
        if ($cursor -lt $line.Length) {
            switch ($line[$cursor]) {
                '"' { $toMatch = '"'; break }
                "'" { $toMatch = "'"; break }
                ')' { $toMatch = '('; break }
                ']' { $toMatch = '['; break }
                '}' { $toMatch = '{'; break }
            }
            if ($toMatch -and $line[$cursor - 1] -eq $toMatch) {
                [Microsoft.PowerShell.PSConsoleReadLine]::Delete($cursor - 1, 2)
                return
            }
        }
    }

    # Nothing to be smart about - just use a Backspace
    [Microsoft.PowerShell.PSConsoleReadLine]::BackwardDeleteChar();

    # If we're backspace-ing a bunch of newlines, recenter the cursor for typewriter-style entry
    if ($line -match '\A[\r\n]+\z') {
        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition(
            [Math]::Floor(($line.Length - 1) / 2)
        );
    }
}

#* Command History

# Command history via F7. This is your per-session history; see below for global history.
Set-PSReadLineKeyHandler -Key F7 `
    -BriefDescription History `
    -LongDescription 'Search the command history and run previous commands' `
    -ScriptBlock {
    # If the console buffer is not empty, use its contents as a search term.
    $pattern = $null;
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref] $pattern, [ref] $null)
    if ($pattern) { $pattern = [regex]::Escape($pattern) }

    # Filter the command history and display in reverse chronological order.
    # The user selects commands (Click/Ctrl+Click/...), then finishes with Enter key/click "OK".
    (
        Get-History -Count 10000 |
        Where-Object { !$pattern -or $_.CommandLine -match $pattern } |
        Sort-Object Id -Descending |
        Out-GridView -Title "Command History$($pattern ? " (regex = $pattern)" : '')" -PassThru |
        Select-Object -ExpandProperty CommandLine # | Get-Unique # ?
    ) -join "`n`n" |
    # The key handler finishes by replacing the buffer's contents with the selection, if any.
    ForEach-Object {
        # Remove double-spacing between #commented #lines.
        # Niche issue in my history - you may not have quite as many "newline-surrounded" comments - but this sometimes makes my output look worse.
        $replace = $_ -replace '(?m)(?<=^[ \t]*#.*$)\n\n(?=^[ \t]*#.*$)', "`n"
        #! This can return an absurd amount of text.
        [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine();
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert($replace);
    }
}

# Global command history via Shift + F7. For session history, see above.
Set-PSReadLineKeyHandler -Key Shift+F7 `
    -BriefDescription History `
    -LongDescription 'Search the command history and run previous commands' `
    -ScriptBlock {
    # If the console buffer is not empty, use its contents as a search term.
    $pattern = $null;
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref] $pattern, [ref] $null)
    if ($pattern) { $pattern = [regex]::Escape($pattern) }

    # For global search, we have to resort to reading from (Get-PSReadLineOption).HistorySavePath.
    # This means we have to find multiline commands and patch them back together. # ! Likely poorly.
    $history = [System.Collections.ArrayList]@(
        $last = ''
        $lines = ''
        foreach ($line in [System.IO.File]::ReadLines((Get-PSReadLineOption).HistorySavePath)) {
            if ($line.EndsWith('`')) {
                $line = $line.Substring(0, $line.Length - 1)
                $lines = if ($lines) {
                    "$lines`n$line"
                }
                else {
                    $line
                }
                continue
            }

            if ($lines) {
                $line = "$lines`n$line"
                $lines = ''
            }

            if (($line -cne $last) -and (!$pattern -or ($line -match $pattern))) {
                $last = $line
                $line
            }
        }
    )
    $history.Reverse()

    $command = ($history | Out-GridView -Title History -PassThru) -join "`n`n"
    if ($command) {
        # Remove double-spacing between commented lines. Even if it sometimes makes output look dumb.
        $replace = $command -replace '(?m)(?<=^[ \t]*#.*$)\n\n(?=[ \t]*#.*$)', "`n"
        #! This can return an absurd amount of text.
        [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert($replace)
    }
}

#* Hotkeyed commands.
# Sometimes, you just need hotkeys. But these go a little further than normal.
# todo: if prompt contains text, copy + clear + re-fill prompt with text; extract to function

# todo: probably don't use ReadKey() - it just sucks
$global:LocationStacks = [ordered]@{} # ordered to keep "default" stack on top of user-defined
Set-PSReadLineKeyHandler -Key Ctrl+j `
    -BriefDescription PushOrPopLocation `
    -LongDescription "Mark the current directory or jump to another directory using PowerShell location stacks." `
    -ScriptBlock {
    param($key, $arg)

    $line = $cursor = $null;
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref] $line, [ref] $cursor);

    # Prompt the user with some basic instructions (and reminder of their hotkeyed stacks)
    $keys = $global:LocationStacks.Keys | Sort-Object -CaseSensitive
    $prompt = "`n    Hit a key to push to that stack"
    $prompt += $keys ? ' or Alt+[' + ($keys -join '|') + '] to pop from that stack' : ' and assign it to this hotkey as a chord (Ctrl+j,key)'
    $prompt += ".`n    [Enter] pushes to the default stack. [Tab] displays all stacks. [Escape] exits."
    [Console]::WriteLine($prompt)
    
    $cki = $null
    $display = $false
    :user_input while ($true) {
        $cki = [Console]::ReadKey($true)

        # Handle predefined keys
        if ($cki.Key -eq [System.ConsoleKey]::Escape) {
            break user_input
        }
        if ($cki.Key -eq [System.ConsoleKey]::Enter) {
            Push-Location
            break user_input
        }
        if ($cki.Key -eq [System.ConsoleKey]::Tab) {
            if (!$display) {
                $display = $true
                $stack_default = [ordered]@{ "default" = Get-Location -Stack }
                $stack_user = $global:LocationStacks ? $global:LocationStacks : @{}
                if ($stack_user.Count -eq 0 -and $stack_default.Values.ToArray().Count -eq 0) {
                    $message = "`n    Location stacks are empty."
                    Write-Host $message -NoNewline
                    $prompt += $message
                }
                else {
                    $stacks = $stack_default + $stack_user
                    $message = "`n`n$($stacks | Format-Table | Out-String)"
                    Write-Host $message -NoNewline
                    $prompt += $message
                }
            }
            continue user_input
        }

        # Handle keys without specific behavior
        if ($cki.Modifiers -band [System.ConsoleModifiers]::Control -ne 0) {
            $message = "`n    Ctrl+$($cki.Key) is not a valid input. Press a key to pushd and hotkey it, or Alt+key to popd from a hotkeyed stack."
            Write-Host $message -NoNewline
            $prompt += $message
            continue user_input
        }
        if ($cki.KeyChar -notmatch '[A-Z0-9]') {
            $message = "`n    $($cki.Key) is not a valid input. To hotkey a stack, the stack name must be a letter or a number."
            Write-Host $message -NoNewline
            $prompt += $message
            continue user_input
        }
        
        # Pop from location stacks
        if ($cki.Modifiers -band [System.ConsoleModifiers]::Alt -ne 0) {
            if ($cki.KeyChar -notin $global:LocationStacks.Keys) {
                # Attempt to get the stack, in case it was modified outside this key handler
                if (!(Get-Location -StackName $cki.KeyChar -EA 0)) {
                    $message = "`n    Invalid input. There is not a stack named $($cki.Key)."
                    Write-Host $message -NoNewline
                    $prompt += $message
                    continue user_input
                }
            }
            Pop-Location -StackName $cki.KeyChar
        }
        # Push to location stacks
        else {
            Push-Location -StackName $cki.KeyChar
        }

        # Since we may have modified this stack outside this function:
        $global:LocationStacks[$cki.KeyChar] = Get-Location -StackName $cki.KeyChar
        break
    }

    # The ways of console shells may mystify but cannot confound us:
    # todo: replace escape sequences correctly; replace Out-String to accomodate VT100; learn more about the console
    $prompt = ($prompt -replace '\S', ' ') + "`n"
    [Microsoft.PowerShell.PSConsoleReadLine]::Insert($prompt) # overwrites prompts 1:1 with spaces+newline
    [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
    [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt() # I don't feel good about this but it works
    return
}


# # MODULES
# # FUNCTIONS
# I use some private modules, several of the well-known community modules, and some basic data processing.
# My functions tend to be very minor utility. Anything you use in serious capacity, try to put in a module.

# # ALIASES
# Use sparingly, to spare frustration; these don't work with our command validation.
# You can use Ctrl+Shift+Enter to run aliased commands that fail to validate on Enter.
Set-Alias -Name os -Value Out-String -Force
function Out-StringArray {
    if ($input) { $input | Out-String -Stream } else { Out-String -Stream }
}
Set-Alias -Name osa -Value Out-StringArray -Force
