#==============================================================================#
# auto-dark-mode.ps1 | efrec.dev@gmail.com | updated 2024-01-21 | test: pass   #
#==============================================================================#
#requires -version 7

# Reminder to set up and test your own paths to your apps, images, etc.

#-------------------------------------------------------------------------------
#---- Initialize ---------------------------------------------------------------

enum ThemeLuminosity {
    Dark  = 0
    Light = 1
}

#-------------------------------------------------------------------------------
#---- Configure ----------------------------------------------------------------

$daylight = @(    # hh, mm, s
    [timespan]::new(09,  0, 0),
    [timespan]::new(19, 45, 0)
)

$winSettings = @{
    Theme   = @{
        Path   = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize'
        Names  = @('AppsUseLightTheme', 'SystemUsesLightTheme')
        Values = @(
            [ThemeLuminosity]::Dark,
            [ThemeLuminosity]::Light
        )
    }
    Desktop = @{
        Path   = "HKCU:Control Panel\Desktop"
        Name   = 'WallPaper'
        Values = @(
            'C:\...\Backgrounds\desktop\italy-tiled-darker.png',
            'C:\...\Backgrounds\desktop\italy-tiled-faded.png'
        )
    }
}

$appSettings = @{
    'Obsidian'         = @{
        File  = 'D:\...\vault_name\.obsidian\appearance.json'
        Theme = 'system'
    }
    'VSCode'           = @{
        File   = 'C:\...\AppData\Roaming\Code\User\settings.json'
        Themes = @('Community Material Theme High Contrast', 'Solarized Light')
    }
    'Windows Terminal' = @{
        File     = 'C:\...\AppData\Local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
        Defaults = $true # Whether to update profiles which use the default scheme.
        Profiles = @('PowerShell', 'pwsh')
        Schemes  = @('One Half Dark', 'iceberg-light') # https://windowsterminalthemes.dev/
    }
}

#-------------------------------------------------------------------------------
#---- Encapsulate --------------------------------------------------------------

function Resolve-DaylightTimeSetup ([array] $times) {
    $times ??= $daylight
    $ticksDay = [timespan]::new(24, 0, 0).Ticks # easiest modulo
    $times[0] = [timespan]::new($daylight[0].Ticks % $ticksDay)
    $times[1] = [timespan]::new($daylight[1].Ticks % $ticksDay)
    return $times | Sort-Object
}

function Test-DaylightTime ([timespan] $time) {
    $time ??= (Get-Date).TimeOfDay
    $start = $daylight[0]
    $end = $daylight[1]
    return ($time -ge $start -and $time -le $end)
}

# # I thought this would be easier, but we need to get into Win32:
function Set-DesktopWallpaper {
    param([Parameter(Mandatory)][String]$PicturePath)
    begin {
        $typeDefinition = @{
            Name             = 'Win32SystemParametersInfo'
            Namespace        = 'Win32Functions'
            MemberDefinition = @"
[DllImport("user32.dll", EntryPoint = "SystemParametersInfo")]
public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
"@
        }
        Add-Type @typeDefinition

        $Action_SetDeskWallpaper = [int]20
        $Action_UpdateIniFile = [int]0x01
        $Action_SendWinIniChangeEvent = [int]0x02
    }
    process {
        # Update registry keys
        Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'WallPaperStyle' -Value 10
        Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'TileWallPaper' -Value 1

        # Pass a message to update the wallpaper -- does more than just setting the key
        $null = [Win32Functions.Win32SystemParametersInfo]::SystemParametersInfo(
            $Action_SetDeskWallpaper,
            0,
            $PicturePath,
            ($Action_UpdateIniFile -bor $Action_SendWinIniChangeEvent)
        )
    }
}

#-------------------------------------------------------------------------------
#---- App-specific functions ---------------------------------------------------

# I wrote this in such an annoying way but not going to rewrite it, so:
function Update-WindowsTerminalProfiles {
    param($settings, $config)

    $settings ??= $appSettings['Windows Terminal']
    $config ??= Get-Content -Path $settings.File | ConvertFrom-Json -Depth 100

    # WT loses settings for some reason (unknown), so we check that our color scheme exists.
    if ($settings.Schemes[$theme] -notin $config.schemes.name) {
        # again just hitting up a random repo basically
        $uri = "https://raw.githubusercontent.com/mbadolato/iTerm2-Color-Schemes/master/windowsterminal/$($settings.Schemes[$theme]).json"
        $ccs = (Invoke-WebRequest -Uri $uri).Content | ConvertFrom-Json -Depth 100
        $config.schemes += $ccs
        $__change = $true
    }

    # WT uses a default profile that's not listed in the profiles collection.
    $changeDefaults = $settings.Defaults -and $config.profiles.defaults.colorScheme -ne $settings.Schemes[$theme]
    if ($changeDefaults) {
        $__change = @{
            InputObject = $config.profiles.defaults
            MemberType  = 'NoteProperty'
            Name        = 'colorScheme'
            Value       = $settings.Schemes[$theme]
        }
        Add-Member @__change -Force
    }

    # WT profiles then use either the default setting or their own color schemes.
    $profiles = $config.profiles.list | ForEach-Object { [pscustomobject]$_ }
    for ($ii = 0; $ii -lt $profiles.Count; $ii++) {
        if (
            $profiles[$ii].Name -in $settings.Profiles -and
            $profiles[$ii].colorScheme -and
            $profiles[$ii].colorScheme -ne $settings.Schemes[$theme]
        ) {
            $__change = @{
                InputObject = $profiles[$ii]
                MemberType  = 'NoteProperty'
                Name        = 'colorScheme'
                Value       = $settings.Schemes[$theme]
            }
            Add-Member @__change -Force
        }
    }

    if ($__change) {
        $config.profiles.list = $profiles
        Copy-Item -Path $settings.File -Destination "$($settings.File).old" -Force -EA 0
        Set-Content -Path $settings.File -Value ($config | ConvertTo-Json -Depth 100)
    }
}

#-------------------------------------------------------------------------------
#---- Execute ------------------------------------------------------------------

$daylight = Resolve-DaylightTimeSetup $daylight
$theme = [ThemeLuminosity] [int] (Test-DaylightTime)

# # OS settings

# Theme
$settings = $winSettings.Theme
Set-ItemProperty -Path $settings.Path -Name $settings.Names[0] -Value $settings.Values[$theme]
Set-ItemProperty -Path $settings.Path -Name $settings.Names[1] -Value $settings.Values[$theme]

# Desktop
$settings = $winSettings.Desktop
Set-DesktopWallpaper -PicturePath $settings.Values[$theme]

# # Application settings

# Obsidian
$settings = $appSettings['Obsidian']
$__config = Get-Content -Path $settings.File | ConvertFrom-Json -Depth 100
$__config.theme = $settings.Theme
# The app doesn't pick up changes to its settings file, until some other change happens.
# I decided it's not worth it to run ipc just to send `app.updateTheme()` once to stdin.
Set-Content -Path $settings.File ($__config | ConvertTo-Json -Depth 100) -Force

# VSCode
$settings = $appSettings['VSCode']
$__config = Get-Content -Path $settings.File | ConvertFrom-Json -Depth 100
$__config.'workbench.colorTheme' = $settings.Themes[$theme]
Set-Content -Path $settings.File ($__config | ConvertTo-Json -Depth 100)

# Windows Terminal
Update-WindowsTerminalProfiles

#-------------------------------------------------------------------------------
#---- Exit ---------------------------------------------------------------------

exit 0
