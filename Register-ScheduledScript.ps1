###############################################################################
#% Script Name	:Register-ScheduledScript.ps1
#% Description	:Sets up a scheduled task without leaving the console.
#%   
#% Library		:
#% Version		:00.00.00 // 2022-10-26
#% Author		:Eric Frechette
#% Email		:efrec.dev@gmail.com
###############################################################################
#% Code Review	:[passing | failing | needed | old | ...] // yyyy-mm-dd
###############################################################################

#requires -RunAsAdministrator

#------------------------------------------------------------------------------
#---- Process Arguments -------------------------------------------------------

param ([string] $user, [string] $script, [hashtable] $settings)
# todo: process $settings, check that $user exists, and validate $script.
# todo: support various triggers (though that's getting tedious).
# todo: stop using this bash template, there are nice pwsh templates


#------------------------------------------------------------------------------
#---- Initialize --------------------------------------------------------------

# todo: there's a broken enum in MultipleInstances; engineer around it.


#------------------------------------------------------------------------------
#---- Encapsulate -------------------------------------------------------------

# todo: additional processing and safety checks should be functionalized.


#------------------------------------------------------------------------------
#---- Execute -----------------------------------------------------------------

# Put your tasks in folders and do not give them clever names.
$task_path = $user -ieq 'system' ? '' : $user
$task_name = Get-Item $script | Select-Object -Expand BaseName || exit 1

# Run your scheduled tasks using service accounts, not users. Non-optional.
$principal = New-ScheduledTaskPrincipal -UserId $user `
    -LogonType ServiceAccount -RunLevel Highest

# And never run them with profiles. Non-optional.
$argument = "-NoProfile -WindowStyle Hidden -File `"$script`""
$action = New-ScheduledTaskAction -Execute 'pwsh.exe' -Argument $argument;

# Register as many triggers as you like.
# Highly repetitious tasks are created awkwardly in pwsh; see next.
$triggers = @(
    (New-ScheduledTaskTrigger -AtLogOn -User $user),
    (New-ScheduledTaskTrigger -Daily -At (Get-Date).Date -DaysInterval 1)
)

# We grab the Repetition field from a repeating-type task and apply it. Easy.
# (Essentially nothing is really, truly read-only in PowerShell, by the by.)
$hourly = $(New-ScheduledTaskTrigger -Once -RandomDelay "00:10" -At "07:00" `
    -RepetitionDuration "08:00" -RepetitionInterval "01:00").Repetition
$triggers[1].Repetition = $hourly

# There's a nontrivial flowchart to determine what your settings ought to be.
# This is the most basic set I could put together, but it has some issues.
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
    -StartWhenAvailable `
    -RestartCount 1 -RestartInterval (New-TimeSpan -Minutes 5)

# Register the task.
Register-ScheduledTask -TaskPath $task_path -TaskName $task_name `
    -Action $action -Principal $principal `
    -Trigger $triggers -Settings $settings || exit 2


#------------------------------------------------------------------------------
#---- Exit --------------------------------------------------------------------
exit 0
