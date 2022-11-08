# pwsh
For the truly misc. scripts

## auto-dark-mode.ps1
PowerShell script to set as a Scheduled Task, for changing your system and app theme to light mode during the day, and to dark mode during nighttime and twilight hours.
It favors dark mode slightly, for preserving your eyes.

## ConvertTo-AsciiArt
Image to "ASCII" (definitely not ASCII) artwork. Uses a nebulous brightness comparison and produces blobby results.
Some characters used may not be safe or display properly, even in monospace.
Working well in Windows Terminal, for starters.

## MultilineEditMode.ps1
If you're learning the CLI after getting comfortable in IDEs, this multiline editing mode can help you out.
It also gives a better experience with pwsh's type checking and other "modern shell" features, directly from the console window.
Normally, pwsh will run an invalid or incorrectly formatted command without validation; this clears your prompt, clutters your history with mistakes, and resets your cursor position.
With this script, when you run a bad command, a syntax error is displayed and your cursor moves right to its location for a faster, easier fix.
Powered by PSReadLine, so it is highly configurable to your needs, with a bit of research.

## Register-ScheduledScript
Creates a scheduled task that runs a .ps1 script in PowerShell v6+.
It's fairly basic and really intended to show how the process works, rather than be comprehensive (which would be more awkward than just learning how to use scheduled tasks).
