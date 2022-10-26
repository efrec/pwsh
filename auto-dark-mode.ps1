###############################################################################
#% Script Name	:auto-dark-mode.ps1
#% Description	:On Windows OS, uses the local time to set the system
#%   and application themes to either light or dark mode.
#% Library		:
#% Version		:00.01.00 // 2022-10-25
#% Author		:Eric Frechette
#% Email		:efrec.dev@gmail.com
###############################################################################
#% Code Review	:[passing | failing | needed | old | ...] // yyyy-mm-dd
###############################################################################

#------------------------------------------------------------------------------
#---- Process Arguments -------------------------------------------------------

# none


#------------------------------------------------------------------------------
#---- Initialize --------------------------------------------------------------

enum ThemeLuminosity {
    Dark = 0
    Light = 1
}
$daylight = @(      #h, m, s
    [timespan]::new(09, 0, 0),
    [timespan]::new(18, 0, 0)
)
$path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize'
$apps = 'AppsUseLightTheme'
$syst = 'SystemUsesLightTheme'


#------------------------------------------------------------------------------
#---- Encapsulate -------------------------------------------------------------

# Fixes the $daylight variable, in case you're a strange person.
function Resolve-DaylightTimeSetup ([array[timespan]] $times) {
    $times ??= $daylight
    if (!$times -or $times.Count -ne 2) {
        return @(
            [timespan]::new(09, 0, 0),
            [timespan]::new(18, 0, 0)
        );
    }

    $daily_ticks = [timespan]::new(24, 0, 0).Ticks
    $times[0] = [timespan]::new($daylight[0].Ticks % $daily_ticks)
    $times[1] = [timespan]::new($daylight[1].Ticks % $daily_ticks)

    return @(
        [math]::Min($times[0], $times[1]).
        [math]::Max($times[0], $times[1])
    )
}

# Checks if our local time is in daylight (according to $daylight).
function Test-DaylightTime ([timespan] $time) {
    $time ??= (Get-Date).TimeOfDay
    $start = [math]::Min($daylight[0], $daylight[1])
    $end = [math]::Max($daylight[0], $daylight[1])
    return ($time -ge $start -and $time -le $end)
}


#------------------------------------------------------------------------------
#---- Execute -----------------------------------------------------------------

$daylight = Resolve-DaylightTimeSetup $daylight
$theme = [ThemeLuminosity] [int] (Test-DaylightTime)
$value = [int] $theme
Set-ItemProperty -Path $path -Name $apps -Value $value || exit 1
Set-ItemProperty -Path $path -Name $syst -Value $value || exit 2


#------------------------------------------------------------------------------
#---- Exit --------------------------------------------------------------------
exit 0
