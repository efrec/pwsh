#requires -version 6;
using namespace System.Management.Automation.Language;

#==================================================================================================#
#=== CurrentUserAllHosts.ps1 | @efrec | 2023-05-12 | passing ======================================#
#                                                                                                  #
#  I use the CurrentUserAllHosts partial profile for consistent dx between hosts.                  #
#  My configuration focuses particularly on vscode and windows terminal.                           #
#                                                                                                  #
#  Target features:                                                                                #
#    Command validation: Enter maps to ValidateAndAcceptLine, not AcceptLine.                      #
#    Smart insert: Auto-indentation and smart paired quotes and braces.                            #
#    Vertical CLI: Enter, Shift+Enter, Ctrl+Enter add (smart) vertical space.                      #
#    Command trimming: Commands are trimmed before running/adding to history.                      #
#    Buried commands: Two spaces before a command suppress it in history.                          #
#                                                                                                  #
#==================================================================================================#

$currentProfile = 'CurrentUserAllHosts'


## ---------------------------------------------------------------------------------------------- ##
## -- Functions --------------------------------------------------------------------------------- ##

function Install-Dependency {
    [CmdletBinding()] param ( [hashtable] $Packages )

    $PackageProperties = 'InstallScript', 'ModuleName', 'TestCommand';
    foreach ($package in $Packages.GetEnumerator()) {
        $key = $package.Name
        $properties = $package.Value

        $TestCommand = $properties.TestCommand ?? $key;
        if ([string]::IsNullOrEmpty($TestCommand)) { continue }
        if (Get-Command $TestCommand -EA 0) { continue }

        # via module repository
        if ($properties | ? ModuleName) {
            $params = @{ Name = $properties.ModuleName }
            $properties.GetEnumerator() | ? Name -notin $PackageProperties | % { $params += $_ }
            if ($null -eq (Get-Module $properties.ModuleName -ListAvailable -EA 0)) {
                Install-Module @params -ErrorAction Continue
            }
            Import-Module @params -ErrorAction Continue
            continue
        }

        # via package manager
        if ($properties | ? ChocolateyName) {
            $params = @('install', $properties.ChocolateyName, '-y')
            if ($properties.ContainsKey('Version')) {
                $params += '--version'
                $params += $properties.Version
            }
            choco @params
            continue
        }

        # via scriptblock
        if ($properties | ? InstallScript) {
            & $properties.InstallScript
            continue
        }
    }
}


## ---------------------------------------------------------------------------------------------- ##
## -- Environment, Variables, Locations --------------------------------------------------------- ##

# Directories
$env:Path += ';C:\ProgramData\chocolatey'
$env:OBSIDIAN_VAULTS = "$env:USERPROFILE\Documents\Vaults\..." <# you'll obviously not use my dir #>

# Windows Terminal variables
$env:WT_SETTINGS_JSON =
    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json";
$env:WT_TAB_SPACES = 4
$env:WT_MAX_NESTING = 12
$env:WT_MAX_NEWLINE = 12

# Default parameter values
$PSDefaultParameterValues = @{
    'Convert*-Json:Depth'       = 100
    'Select-First:First'        = 1
    '*:Encoding'                = 'utf8'
    '*-GitHub?*:Owner'          = 'efrec'
    '*-GitHub?*:RepositoryName' = 'lol'
    '*-GitHub?*:Token'          = $env:PSGithubToken | ConvertTo-SecureString
}


## ---------------------------------------------------------------------------------------------- ##
## -- Package Managers, Modules, Commands ------------------------------------------------------- ##

# Your package managers are not be guaranteed. Start with them.
$PackageManagers = @{
    'choco' = @{
        InstallScript = { iwr -UseBasicParsing -Uri 'https://chocolatey.org/install.ps1' | iex }
        TestCommand   = 'choco'
    }
}

# Packages can install from PSGallery, Chocolatey, or a script.
# Modules that must run in background must use an import script.
$Packages = @{
    'az'         = @{ ChocolateyName = 'azure-cli'                             }
    'ssh'        = @{ ChocolateyName = 'openssh'                               }
    'openssl'    = @{ ChocolateyName = 'openssl' ; TestCommand = 'openssl.exe' }
    'git'        = @{ ChocolateyName = 'git.install'                           }
    'base64'     = @{ ChocolateyName = 'base64'                                }
    'node'       = @{ ChocolateyName = 'nodejs-lts'                            }
    'winscp'     = @{ ChocolateyName = 'winscp'                                }
    'ripgrep'    = @{ ChocolateyName = 'ripgrep' ; TestCommand = 'rg'          }
    'docker'     = @{ ChocolateyName = 'docker-desktop'                        }
    'terraform'  = @{ ChocolateyName = 'terraform'                             }
    'PSCX'       = @{ ModuleName     = 'Pscx'                                  }
    'PSGithub'   = @{ ModuleName     = 'PSGithub'                              }
    'MarkdownPS' = @{ ModuleName     = 'MarkdownPS'                            }
}

# Here's where all our startup time comes from. It's worth it.
Install-Dependency $PackageManagers
Install-Dependency $Packages

# Chocolatey uses a module as a subprofile.
$chocolateyProfile = "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
if (Test-Path $chocolateyProfile) { Import-Module "$chocolateyProfile" }

# Commands that haven't been put in a module.
$miscCommands = @{
    'ConvertTo-MarkdownTable' = "$env:USERPROFILE\...\pwsh\profile\ConvertTo-MarkdownTable.ps1"
    'ConvertTo-TextArt'       = "$env:USERPROFILE\...\pwsh\display\text-art.ps1"
    'Get-NewSessionMessage'   = "$env:USERPROFILE\...\pwsh\display\Get-NewSessionMessage.ps1"
    'Merge-Hashtable'         = "$env:USERPROFILE\...\pwsh\profile\Merge-Hashtable.ps1"
    'Search-Registry'         = "$env:USERPROFILE\...\admin\profile\Search-Registry.ps1"
    'Set-UserKeyHandling'     = "$env:USERPROFILE\...\pwsh\console\Set-UserKeyHandling.ps1"
    'Test-XmlFile'            = "$env:USERPROFILE\...\pwsh\profile\Test-XmlFile.ps1"
}
$miscCommands.Values | Sort-Object -Unique | ForEach-Object { . $_ }


## ---------------------------------------------------------------------------------------------- ##
## -- PSReadLine -------------------------------------------------------------------------------- ##

# While we are at it:
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

## -- Prompt, Predictions, History -------------------------------------------------------------- ##

# Prompt
. "$env:USERPROFILE\Documents\VSCode\admin\profile\prompt.ps1"
Get-KnownFolders -UseFullNames -SetGlobalVariable | Out-Null
Set-PSReadLineOption -ContinuationPrompt '' -PromptText ''

# Command predictions and help
# On accept-and-execute, this duplicates the command (e.g. `clscls`), so I do not use it anymore:
# Set-PSReadLineOption -PredictionViewStyle ListView

# Command history
$commandHistoryHandler = @{
    HistoryNoDuplicates = $false
    HistorySaveStyle    = [Microsoft.PowerShell.HistorySaveStyle]::SaveIncrementally
    <# As of mid 2022, PSReadLine implements a competent sensitivity test as its default. #>
    <# We are going to wrap that method and handle a few additional cases around it. #>
    AddToHistoryHandler = {
        param([string] $line)
        <# spammy #> if ($line -in 'exit', 'ls', 'pwd', 'cls', 'clear' ) { return $false }
        <# hidden #> if ($line -match '\A[ ]{2}\S') <# 2 spaces hides #> { return $false }
        <# assist #> if ($line -match <# suppress common help commands, when they're genuine #>
            '(?<=^|\b)(?<![$-]|(^|\b)set(-variable)? )(help|get-help|man)(?=\b|$)(?![:-]| *=)') {
            $sensitive = ![Microsoft.PowerShell.PSConsoleReadLine]::GetDefaultAddToHistoryOption($line)
            return $sensitive ? $false : [Microsoft.PowerShell.AddToHistoryOption]::MemoryOnly
        }
        <# secret #> if ($line -match 'password|passphrase|pw|asplaintext|secure|key|token') {
            return [Microsoft.PowerShell.PSConsoleReadLine]::GetDefaultAddToHistoryOption($line)
        }
        <# normal #> return [Microsoft.PowerShell.AddToHistoryOption]::MemoryAndFile
    }
}
Set-PSReadLineOption @commandHistoryHandler

## -- Hotkeys ----------------------------------------------------------------------------------- ##

# General Key Handlers

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
        #? Newline displays as ^M and messes with arrow key movement. No idea how to replace.
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

# Hotkeyed Commands

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
        $usage += $keys ?
        ' or Alt+[' + ($keys -join '|') + '] to pop from that stack.' :
        ' and assign it to this hotkey as a chord (Ctrl+j,key).'
        $usage += "`n    [Enter] pushes to the default stack. [Tab] displays all stacks. [Escape] exits."
        [Console]::WriteLine($usage)

        # Process
        $start_location = Get-Location
        $stack_default = [ordered]@{ "default" = Get-Location -Stack }
        $display = $false

        :user_input while ($response = [Console]::ReadKey($true)) {
            # Handle improper input
            if (($response.Modifiers -band [System.ConsoleModifiers]::Control) -ne 0) {
                $message = "`n    Ctrl is not a valid modifier.`n    Press a key to pushd and hotkey it, or use Alt+key to popd from a key's stack."
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
                    $message = "`n    There is no stack hotkeyed to $($response.Key)."
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
        $prompt = ($prompt + "`n`n`n") -replace '[^\n\r]', ' '
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert($prompt)
        [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()

        # On a jump, update the prompt's path display.
        if ($start_location.FullName -ne $end_location.FullName) {
            [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
        }
    }
}
Set-PSReadLineKeyHandler @locationStacksHandler


## ---------------------------------------------------------------------------------------------- ##
## -- Aliases ----------------------------------------------------------------------------------- ##

## -- pwsh -------------------------------------------------------------------------------------- ##

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

## -- bash -------------------------------------------------------------------------------------- ##

if (-not (Get-Command 'grep' -EA 0)) {
    function grep { $input | Out-String -stream | Select-String $args }
}

## -- slaps ------------------------------------------------------------------------------------- ##
# Not all user behavior can be treated gently. Guards — slap this man.

function Write-RipgrepAliasSlap { Write-Warning "ripgrep => rg, for like forever, come on" }
Set-Alias -Name ripgrep -Value Write-RipgrepAliasSlap


## ---------------------------------------------------------------------------------------------- ##
## -- Cleanup ----------------------------------------------------------------------------------- ##

# Remove variables -- for when we inevitably dot-source this file -- beware data loss.
Remove-Variable -Name (
    '*?Profile?',
    '*?Command?',
    '*?Handler$'
) -EA 0


## ---------------------------------------------------------------------------------------------- ##
## -- Banner ------------------------------------------------------------------------------------ ##

# Clear the launch logo and insert our own.
# Use -Force:$true to ignore -NoLogo:$false.
Get-NewSessionMessage -Force:$(-not (Get-History -Count 1))
