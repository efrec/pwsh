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
Easy multiline commands right from the console window.
"Multiline mode" changes the behavior of the Enter key in a few ways; read the file for more info.
There's nothing like an IDE, but PSReadLine has a few strong utilities that help with daily cli use.
In particular, this performs validation when you run a command.
For example, if you input imbalanced parens, this displays your error message and moves your cursor to the end of the offending region.

## Register-ScheduledScript
Creates a scheduled task that runs a .ps1 script in PowerShell v6+.
It's fairly basic and really intended to show how the process works, rather than be comprehensive (which would be more awkward than just learning how to use scheduled tasks).
