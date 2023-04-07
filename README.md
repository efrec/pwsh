# pwsh
A handful of miscellaneous pwsh scripts.
These had no home while I was working on them + setting up this github acct.

#### auto-dark-mode.ps1
Simple script to set up as a scheduled task.
Changes both your system and app theme to light mode during the day and to dark mode during darker hours.

#### ConvertTo-TextArt
Provides two functions for producing text art, generally well-suited for images with soft edges/shapes.
This mini hobby project is now functional enough to recommend to others.

<blockquote>
<dl>

  <dt>Get-CharacterLuminosityMap</dt>
  <dd>
The map function quickly builds a text-art palette for reuse with the text art converter.
This palette considers the shape and proportions of each character, not just their overall painted area.
  </dd>
  
  <dt>ConvertTo-TextArt</dt>
  <dd>
The text art conversion runs a subpixel comparison of the input image against your character map.
Its -Smoothing parameter allows you to fit more closely on overall pixel brightness, instead of by shape, up to a limit.
The calculations used in this comparison have been simplified to present a comprehensible algorithm, without too much quality loss, but there is room to improve.
  </dd>
  
</dl>
</blockquote>

#### CurrentUserAllHosts.ps1
CurrentUserAllHosts is one of the files that constitutes your pwsh profile.
It's loaded whenever you start a new terminal, so you can use it for a consistent user experience.
I wanted a better editing experience in Windows Terminal without using vi mode.
This is a modern-feeling editor specifically for pwsh directly in terminal.
It makes better use of type checking and other modern-shell features by running on the compiled commands, not plaintext.

#### Register-ScheduledScript
Creates a scheduled task that runs a .ps1 script in PowerShell v6+.
It's intended to show how the process works rather than be comprehensive—which would be more awkward than just learning how to use scheduled tasks.
