# Add to your profile to get some interesting multiline command editing from the console.

# This key handler features:
# (1) Command validation. Checks for mistyped commands, mismatched parens, incorrect operators, etc.
# (2) Vertically expands. Hitting Enter repeatedly adds new lines, like Shift+Enter.
# (3) Command trimming. Extra vertical space is removed when running commands.
# (4) Preserves buried commands. Two spaces before a command is commonly hidden from history.

$mutliline_expand = {
    param($key)
    # Get the current contents of the prompt.
    $line = $cursor = $null;
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref] $line, [ref] $cursor);
    # If buffer is empty, except for newlines...
    if ($line -match '^[\r\n]*$') {
        # ...move to the middle of the buffer, then insert another line.
        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition(
            [System.Math]::Floor(([double] $line.Length) / 2)
        );
        [Microsoft.PowerShell.PSConsoleReadLine]::InsertLineBelow();
    }
    # Commands preceded with 2 spaces (exactly) are being buried by user:
    elseif ($line -match '\A[ ]{2}\S') {
        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine();
    }
    else {
        # Trim, validate, and accept input.
        $replace = $line -replace '\A\s*|\s*\z', '';
        [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine();
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert($replace);
        [Microsoft.PowerShell.PSConsoleReadLine]::ValidateAndAcceptLine();
    }
}
Set-PSReadLineKeyHandler -Chord Enter -ScriptBlock $mutliline_expand
