#=============================================================================#
# CurrentUserAllHosts.ps1 | @efrec | 2023-05-12 | passing 2023-05-12          #
#=============================================================================#
# I use my CurrentUserAllHosts profile for consistent dx between hosts.
# This partial profile focuses particularly on vscode and windows terminal.
# # Short list of features:
# (1) Command validation. Enter maps to ValidateAndAcceptLine, not AcceptLine.
# (2) Smart insert. Auto-indentation and smart paired quotes and braces.
# (3) Vertical CLI. Enter, Shift+Enter, Ctrl+Enter add (smart) vertical space.
# (4) Command trimming. Commands are trimmed before running/adding to history.
# (5) Buried commands. Two spaces before a command suppress it in history.

#requires -version 7;
using namespace System.Management.Automation.Language;


# # ENVIRONMENT, VARIABLES, LOCATIONS

# Windows Terminal
$env:WT_SETTINGS_JSON = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
$env:WT_TAB_SPACES = 4
$env:WT_MAX_NESTING = 12

# Directory 
$env:OBSIDIAN_VAULTS = "$env:USERPROFILE\Documents\Vaults\git-sync"

## PowerShell globals
$PSDefaultParameterValues = @{
    'Convert*-Json:Depth'       = 100
    '*-GitHub?*:Owner'          = 'efrec'
    '*-GitHub?*:RepositoryName' = 'backup'
    '*-GitHub?*:Token'          = $env:PSGithubToken | ConvertTo-SecureString
}


# # MODULES, SUBPROFILES

# Module support
# note: includes change to `refreshenv`
$chocolateyProfile = "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
if (Test-Path $chocolateyProfile) { Import-Module "$chocolateyProfile" }

# Modules
Import-Module 'Pscx'
Import-Module 'PSGitHub'
Import-Module 'MarkdownPS'
# Import-Module 'ClassExplorer'
# Some modules have to run in the background:
#?Import-CommandSuite # EditorServicesCommandSuite
#?Start-Commander # PSCommander


# # DOTFILES

$miscCommands = @{
    'ConvertTo-MarkdownTable' = "$env:USERPROFILE\Documents\VSCode\admin\profile\ConvertTo-MarkdownTable.ps1"
    'ConvertTo-TextArt'       = "$env:USERPROFILE\Documents\VSCode\pwsh\display\text-art.ps1"
    'Get-NewSessionMessage'   = "$env:USERPROFILE\Documents\VSCode\pwsh\display\Get-NewSessionMessage.ps1"
    'Merge-Hashtable'         = "$env:USERPROFILE\Documents\VSCode\admin\profile\Merge-Hashtable.ps1"
    'Search-Registry'         = "$env:USERPROFILE\Documents\VSCode\admin\profile\Search-Registry.ps1"
    'Set-UserKeyHandling'     = "$env:USERPROFILE\Documents\VSCode\pwsh\console\Set-UserKeyHandling.ps1"
    'Test-XmlFile'            = "$env:USERPROFILE\Documents\VSCode\admin\profile\Test-XmlFile.ps1"
}
$miscCommands.Values | Sort-Object -Unique | ForEach-Object { . $_ }


# # PSREADLINE: PROMPT, PREDICTIONS, HISTORY

# Prompt
. "$env:USERPROFILE\Documents\VSCode\admin\profile\prompt.ps1"
Get-KnownFolders -UseFullNames -SetGlobalVariable | Out-Null
Set-PSReadLineOption -ContinuationPrompt '' -PromptText '' # idk if empty text is bad here

# Command predictions
# ? this broke all kinds of things; what the hell, pwsh?
# Set-PSReadLineOption -PredictionViewStyle ListView

# Command history
$commandHistoryHandler = @{
    HistoryNoDuplicates = $false
    HistorySaveStyle    = [Microsoft.PowerShell.HistorySaveStyle]::SaveIncrementally
    # As of ~mid 2022, PSReadLine implements a competent sensitivity test.
    # We are going to wrap that method to evaluate a few additional cases.
    AddToHistoryHandler = {
        param([string] $line)
        <# spammy #> if ($line -in 'exit', 'ls', 'pwd', 'cls', 'clear' ) { return $false }
        <# buried #> if ($line -match '\A[ ]{2}\S') { return $false }
        <# assist #> if ($line -match '(?<=^|\b)(?<!\$)(help|get-help|man)(?=\b|$)(?![-:]| *=)') {
            $sensitive = -not [Microsoft.PowerShell.PSConsoleReadLine]::GetDefaultAddToHistoryOption($line)
            return $sensitive ? $false : [Microsoft.PowerShell.AddToHistoryOption]::MemoryOnly
        }
        <# secret #> if ($line -match 'password|asplaintext|securestring|from-secure|to-secure|key|token') {
            return [Microsoft.PowerShell.PSConsoleReadLine]::GetDefaultAddToHistoryOption($line)
        }
        <# normal #> return [Microsoft.PowerShell.AddToHistoryOption]::MemoryAndFile
    }
}
Set-PSReadLineOption @commandHistoryHandler


# # PSREADLINE: HOTKEYS

#* General Key Handlers

# Smart Enter key, paired quotes/brackets, etc.
Set-UserKeyHandling -ModernMultiline | Out-Null

# Paste values only
# Note: The Ctrl+Shift+v action in Windows Terminal intercepts this.
$pasteValuesOnlyHandler = @{
    Chord            = 'Ctrl+Shift+v'
    BriefDescription = 'PasteValuesOnly'
    LongDescription  = 'Paste clipboard text as ANSI text. Has an issue with newlines.'
    ScriptBlock      = {
        $values = (Get-Clipboard -Text) -join "`n"
        #? Newline displays as ^M and messes with arrow key movement.
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert($values)
    }
}
Set-PSReadLineKeyHandler @pasteValuesOnlyHandler

# Command session history
$commandHistorySessionHandler = @{
    Chord            = 'F7'
    BriefDescription = 'SessionHistoryPopout'
    LongDescription  = 'Search the command history interactively and run previous commands with multi-select.'
    ScriptBlock      = {
        $line = $null;
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref] $line, [ref] $null)

        if ($line) { $pattern = [regex]::Escape($line) }
        $gridView = @{
            Title    = "Session History$($pattern ? " (regex = $pattern)" : '')"
            PassThru = $true
        }
        if (!($history = Get-History | Where-Object CommandLine -Match $pattern)) {
            $newLines = $line.Split("`n").Count
            $message = $pattern ? 'No matching commands were found.' : 'No commands found in session history.'
            Write-Host "$("`n" * $newLines)$($PSStyle.Italic)$message" -NoNewline
            return
        }
        $history | Out-GridView @gridView |
        Select-Object -ExpandProperty CommandLine -Unique |
        Where-Object Length | ForEach-Object -Begin {
            $command = ''
        } -Process {
            $command = $command, $_ -join "`n`n"
        } -End {
            # Squish #commented lines together to take less space.
            $command = $command -replace '(?m)(?<=^[ \t]*#.*$)\n\n(?=^[ \t]*#.*$)', "`n"
            # Replace the buffer with the selected commands.
            [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine();
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($command);
        }
    }
}
Set-PSReadLineKeyHandler @commandHistorySessionHandler

# Command global history
$commandHistoryGlobalHandler = @{
    Chord            = 'Shift+F7'
    BriefDescription = 'GlobalHistoryPopout'
    LongDescription  = 'Search the (global) command history interactively and run previous commands with multi-select.'
    ScriptBlock      = {
        $line = $null;
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref] $line, [ref] $null)

        $historySavePath = (Get-PSReadLineOption).HistorySavePath
        $historyFromFile = [System.Collections.ArrayList]@(
            $lines = ''
            $allLines = [System.IO.File]::ReadLines($historySavePath).GetEnumerator()
            foreach ($part in $allLines) {
                if ($part.EndsWith('`')) {
                    $part = $part.Substring(0, $part.Length - 1)
                    $lines = if ($lines) { "$lines`n$part" } else { $part }
                    continue
                }
                if ($lines) {
                    $part = "$lines`n$part"
                    $lines = ''
                }
                if ($part -match $pattern) {
                    $count++
                    $part
                }
            }
        )

        if ($line) { $pattern = [regex]::Escape($line) }
        $gridView = @{
            Title    = "Global History$($pattern ? " (regex = $pattern)" : '')"
            PassThru = $true
        }
        if (!($history = $historyFromFile | Where-Object CommandLine -Match $pattern)) {
            $newLines = $line.Split("`n").Count
            $message = $pattern ? 'No matching commands were found.' : 'No commands found in global history.'
            Write-Host "$("`n" * $newLines)$($PSStyle.Italic)$message" -NoNewline
            return
        }
        $history | Out-GridView @gridView |
        ForEach-Object -Begin {
            $command = ""
        } -Process {
            $command = $command, $_ -join "`n`n"
        } -End {
            # Squish #commented lines together to save space.
            $command = $command -replace '(?m)(?<=^[ \t]*#.*$)\n\n(?=[ \t]*#.*$)', "`n"
            # Replace buffer with the selected commands.
            [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($command)
        }
    }
}
Set-PSReadLineKeyHandler @commandHistoryGlobalHandler


#* Hotkeyed Commands

# Jump directories
$global:LocationStacks = [ordered]@{}
$locationStacksHandler = @{
    Chord            = 'Ctrl+j'
    BriefDescription = 'PushOrPopLocation'
    LongDescription  = 'Mark directories and jump between them using the pwsh location stacks.'
    ScriptBlock      = {
        $line = $cursor = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref] $line, [ref] $cursor)
        
        # Usage
        $keys = $global:LocationStacks.Keys | Sort-Object -CaseSensitive
        $usage = "`n    Hit a key to push to that stack"
        $usage += $keys ? ' or Alt+[' + ($keys -join '|') + '] to pop from that stack' : ' and assign it to this hotkey as a chord (Ctrl+j,key)'
        $usage += ".`n    [Enter] pushes to the default stack. [Tab] displays all stacks. [Escape] exits."
        [Console]::WriteLine($usage)

        # Process
        $start_location = Get-Location
        $stack_default = [ordered]@{ "default" = Get-Location -Stack }
        $display = $false

        :user_input while ($response = [Console]::ReadKey($true)) {
            # Handle improper input
            if (($response.Modifiers -band [System.ConsoleModifiers]::Control) -ne 0) {
                $message = "`n    Ctrl+$($response.Key) is not a valid input.`n    Press a key to pushd and hotkey it, or use Alt+key to popd from a key's stack."
                Write-Host $message -NoNewline
                $prompt += $message
                continue user_input
            }
            if ($response.Key -notmatch '^(?:[A-Z0-9]|Tab|Escape|Enter)$') {
                $message = "`n    $($response.Key) is not a valid input. To hotkey a stack, the stack name must be a letter or a number."
                Write-Host $message -NoNewline
                $prompt += $message
                continue user_input
            }

            # Handle predefined keys
            if ($response.Key -eq [System.ConsoleKey]::Escape) {
                break user_input
            }
            if ($response.Key -eq [System.ConsoleKey]::Enter) {
                Push-Location
                break user_input
            }

            # Handle display of jump stacks
            if ($response.Key -eq [System.ConsoleKey]::Tab) {
                if ($display) { continue user_input }
                $display = $true
                if (!($stacks = $stack_default + $global:LocationStacks).Count) {
                    $message = "`n    Location stacks are empty."
                    Write-Host $message -NoNewline
                    $prompt += $message
                    continue user_input
                }
                $message = "`n$($stacks | Format-Table -Wrap | Out-String)"
                Write-Host $message -NoNewline
                $prompt += $message
                continue user_input
            }

            # Pop from input location stack
            if ($response.Modifiers -eq [System.ConsoleModifiers]::Alt) {
                if ([char]$response.Key -notin $global:LocationStacks.Keys) {
                    $message = "`n    Invalid input. There is not a stack hotkeyed to $($response.Key)."
                    Write-Host $message -NoNewline
                    $prompt += $message
                    continue user_input
                }
                Pop-Location -StackName $response.Key
                break user_input
            }

            # Push to input location stack
            Push-Location -StackName $response.Key
            $global:LocationStacks[[char]$response.Key] = Get-Location -StackName $response.Key
            break user_input
        }

        $end_location = Get-Location

        # Whiteout and revert everything written to the host.
        Write-Host ""
        $prompt = ($prompt + "`n`n`n") -replace '\S', ' '
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert($prompt)
        [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()

        # On a jump, update the prompt's path display.
        if ($start_location.FullName -ne $end_location.FullName) {
            [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
        }
    }
}
Set-PSReadLineKeyHandler @locationStacksHandler


# # ALIASES

# Shorthands
Set-Alias -Name 'from-csv'    -Value ConvertFrom-Csv          -Force
Set-Alias -Name 'to-csv'      -Value ConvertTo-Csv            -Force
Set-Alias -Name 'from-json'   -Value ConvertFrom-Json         -Force
Set-Alias -Name 'to-json'     -Value ConvertTo-Json           -Force
Set-Alias -Name 'from-secure' -Value ConvertFrom-SecureString -Force
Set-Alias -Name 'to-secure'   -Value ConvertTo-SecureString   -Force

function Out-StringArray { if ($input) { $input | Out-String -Stream } else { Out-String -Stream } }
Set-Alias -Name os  -Value Out-String      -Force
Set-Alias -Name osa -Value Out-StringArray -Force

# Reminders / slaps
function Get-RipgrepAlias { Write-Host "$($input.Current ? $input : 'the ripgrep.exe command') => rg" }
Set-Alias -Name ripgrep -Value Get-RipgrepAlias


# # CLEANUP

# Remove variables -- for when we inevitably dot-source this file -- beware data loss.
Remove-Variable -Name (
    '*?Profile?',
    '*?Command?',
    '*?Handler?'
) -EA 0


# # BANNER
# Clear the launch logo and insert our own.
# Use -Force:$true to ignore -NoLogo:$false.
Get-NewSessionMessage -Force:$(-not (Get-History -Count 1))
