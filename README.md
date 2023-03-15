# pwsh
For the truly misc. scripts

## auto-dark-mode.ps1
PowerShell script to set as a Scheduled Task, for changing your system and app theme to light mode during the day, and to dark mode during nighttime and twilight hours.
It favors dark mode slightly, for preserving your eyes.

## ConvertTo-AsciiArt
Image to "ASCII" (definitely not ASCII) artwork. Uses a nebulous brightness comparison and produces blobby results.
Some characters used may not be safe or display properly, even in monospace.
Working well in Windows Terminal, for starters.

## CurrentUserAllHosts.ps1
One of the files that constitutes your pwsh profile. Loaded whenever you start a new terminal, just like your profile.
If you're learning the CLI after getting comfortable in IDEs, this "multiline" (-ish) editing mode can help you out.
It also gives a better experience with pwsh's type checking and other "modern shell" features, natively in the console.
This is powered by PSReadLine, so should be configurable to your needs. Doesn't support vi mode yet.

## Register-ScheduledScript
Creates a scheduled task that runs a .ps1 script in PowerShell v6+.
It's intended to show how the process works rather than be comprehensive (which is far more awkward than just learning how to use scheduled tasks).
