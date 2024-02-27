using namespace System.Management.Automation.Language;

function Set-UserKeyHandling {
    [CmdletBinding()]
    param (
        [Parameter(ParameterSetName = 'System-PSReadLine-Defaults')]
        [switch] $RestoreDefaults,

        # Load in all key handlers, overriding the built-in handlers.
        [Parameter(ParameterSetName = 'System-PSReadLine-Enhancements')]
        [switch] $ModernMultiline,

        # Load in a single group of key handlers from the configs.
        [Parameter(ParameterSetName = 'System-PSReadLine-Enhancements-Set')]
        [string] $HandlerSetName,

        # Load in a single key handler from the configs.
        [Parameter(ParameterSetName = 'System-PSReadLine-Enhancements-Key')]
        [string] $KeyHandlerName,

        # Load in key handlers without overriding any built-in handlers.
        [Parameter(ParameterSetName = 'User-PSReadLine-Enhancements')]
        [switch] $EnhancementsOnly
    )

    #---- Initialize -------------------------------------------------------------------------------

    # This function just loads and picks through a pwsh data file:
    if (-not ($keyHandlerFile = Get-Item -Path "$PSScriptRoot\PSReadLine-KeyHandlers.psd1") -and
        -not ($keyHandlerFile = Get-Item -Path "$env:USERPROFILE\...\pwsh\console\PSReadLine-KeyHandlers.psd1")) {
        throw new 'The data file "psreadline-keyhandlers.psd1" was not found.'
    }

    #---- Process ----------------------------------------------------------------------------------

    Invoke-Expression -Command (Get-Content $keyHandlerFile -Raw)
    if (!$PSReadLineKeyHandlers) { throw new 'Could not retrieve key handlers.' }

    # I wanted to experiment with more descriptive param set names instead of the humanized params.
    # This is somewhat less readable but very thorough-seeming. Not sure who this would impress.

    switch ($PSCmdlet.ParameterSetName) {

        # System - Overrides default, built-in key handlers (e.g. Enter, Tab, Ctrl+C).

        'System-PSReadLine-Defaults' {
            $userDefined = [Microsoft.PowerShell.KeyHandlerGroup]::Custom
            if (Get-PSReadLineKeyHandler -Bound | Where-Object Group -Eq $userDefined) {
                throw new 'Default key handlers have been modified.'
            }
        }

        'System-PSReadLine-Enhancements' {
            # The 'ModernMultiline' set uses specific key handler sets.
            foreach ($params in $PSReadLineKeyHandlers.SmartInsertDelete) {
                Set-PSReadLineKeyHandler @params -Verbose
            }
            foreach ($params in $PSReadLineKeyHandlers.SmartMultiline) {
                Set-PSReadLineKeyHandler @params -Verbose
            }
        }

        'System-PSReadLine-Enhancements-Set' {
            foreach ($params in ($PSReadLineKeyHandlers | ? Key -eq $HandlerSetName | % { $_ })) {
                Set-PSReadLineKeyHandler @params -Verbose
            }
        }

        'System-PSReadLine-Enhancements-Key' {
            # A bit of a pain: This is a hashtable of key-strings to value-arrays of hashtables.
            $PSReadLineKeyHandlers | ForEach-Object {
                $_.GetEnumerator() | ForEach-Object {
                    $_.Value | Where-Object {
                        $KeyHandlerName -eq $_.Description -or
                        $KeyHandlerName -eq $_.BriefDescription
                    } | ForEach-Object { $params = $_; Set-PSReadLineKeyHandler @params }
                }
            }
        }

        # User - Will not override built-in key handlers. This is likely better practice. Oh well.

        'User-PSReadLine-Enhancements' {
            $boundKeys = (Get-PSReadLineKeyHandler -Bound).Key;
            (  $PSReadLineKeyHandlers.SmartInsertDelete +
               $PSReadLineKeyHandlers.SmartMultiline  ) |
            Where-Object Chord -NotIn $boundKeys |
            ForEach-Object { $params = $_; Set-PSReadLineKeyHandler @params }
        }
    }

    # Clean up afterward.
    Remove-Variable -Name PSReadLineKeyHandlers -ErrorAction SilentlyContinue
}
