# pwsh
A handful of truly miscellaneous pwsh scripts.
These had no home while I was working on them + setting up this github acct.

#### auto-dark-mode.ps1
Simple script to set up as a scheduled task.
Changes both your system and app theme to light mode during the day and to dark mode during darker hours.

#### ConvertTo-AsciiArt
Image to text art; definitely no longer ASCII-only.
Runs a comparison of pixel brightness against the relative areas of a list of characters.
Optionally, runs a comparison of the surrounding pixels/subpixels to match the shapes of asymmetric characters.
Different fonts use different areas, shapes, and proportions, which will impact the visual quality.

#### CurrentUserAllHosts.ps1
One of the files that constitutes your pwsh profile.
Loaded whenever you start a new terminal.
This provides a better command editing experience directly in Windows Terminal without switching to vi mode.
It also gives a better experience with pwsh's type checking and other nominally modern-shell features, powered entirely by PSReadLine.
Doesn't support vi mode yet, but should.

#### Register-ScheduledScript
Creates a scheduled task that runs a .ps1 script in PowerShell v6+.
It's intended to show how the process works rather than be comprehensive—which would be more awkward than just learning how to use scheduled tasks.
