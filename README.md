# pwsh
A handful of miscellaneous pwsh scripts.
These had no home while I was working on them + setting up this github acct.

#### auto-dark-mode.ps1
Simple script to set up as a scheduled task.
Changes both your system and app theme to light mode during the day and to dark mode during darker hours.

#### ConvertTo-AsciiArt
Image to text art; definitely no longer ASCII-only.
Runs a comparison of pixel brightness against the relative areas of a list of characters.
Optionally, runs a comparison of the surrounding pixels/subpixels to match the shapes of asymmetric characters.
Different fonts have different areas, shapes, and proportions, which will impact the visual quality.

#### CurrentUserAllHosts.ps1
CurrentUserAllHosts is one of the files that constitutes your pwsh profile.
It's loaded whenever you start a new terminal, so you can use it for a consistent user experience.
I wanted a better editing experience in Windows Terminal without using vi mode.
This is a modern-feeling editor specifically for pwsh directly in terminal.
It makes better use of type checking and other modern-shell features by running on the compiled commands, not plaintext.

#### Register-ScheduledScript
Creates a scheduled task that runs a .ps1 script in PowerShell v6+.
It's intended to show how the process works rather than be comprehensive—which would be more awkward than just learning how to use scheduled tasks.
