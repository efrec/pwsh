using namespace System.Collections
using namespace System.Collections.Generic
using namespace System.Management.Automation
using namespace System.Management.Automation.Language

# # VARIABLES
enum BmpToAsciiType {
    Pixel = 0
    PixelAndSubpixel = 1
    Subpixel = 2
}

# # FUNCTIONS

<#
.SYNOPSIS
    Loads an image from file and converts to ASCII text art. (Aliases: aa, asciiart)
.DESCRIPTION
    ConvertTo-AsciiArt takes a sample image file and converts it to a simple bitmap (no transparency) scaled to an output font display height.

    It has a fast mode, which compares text characters to the brightness level of a single (bitmap) pixel, and a slower mode with subpixel precision, also compared on brightness. The subpixel comparison can be tuned to match overall brightness as well as possible, or to match the distribution of brightness across subpixels as well as possible, and any range between.
.NOTES
    Colors and other font styling are not supported.
    "Slow mode" is the least optimized possible, almost wrong on purpose, but tolerable for most images.
    The character palette is in need of a new approach, preferably a programmatic one.
.LINK
    https://github.com/efrec/pwsh
.EXAMPLE
    ConvertTo-AsciiArt -Path C:\Users\Pictures\she_must_be_that.jpg -MaxWidth 60 -BmpToAsciiType Subpixel -BrightnessShapeRatio 0.5 -DisplayRatio 2.2
`````````´`´´´´´´´´´´´´´´´´´´´´.⁖⁖...´´´´´´´´.´´.´´´.´´´..´⁖
.............................veZ7¾%%¾e\⁖....................
........................._vwa⩩⩩@%%@@@E@¾⌗‛..................
...................__wJ6⩩⩩⩩%üüZPE%%Z%++Z¾\⁖´................
................⁖o⩩@&&&@@@@@@@%¾+¼7PZ¾++¼/\:................
...............w⩩&&&&&&E@@@@@ZZZ%Z\:⁖/>¼:'d\................
.............⁖J@@&E@@@&P@@@@@ZZ⩩ZY>"::`⁖/:d+`⁖.......   ....
.............d%⩩⩩&&@@@Z++YYYZ@>>7>.´‾:⁖⁖:.J%`⁖:...       ...
............⁖J&&&&&&&@%Y+¾::?/"..⁖⁖⁖⁖.`⁖⁖´dZ`.?`.         ..
............d@E&&&&&&E@%¾\:`.´´`´.⁖‛⁖⁖⁖.../Z:./`         ...
.....   .  ./+P@&PY++üZZ%Y⌗`´´......´⁖⁖``´ Z¼`/\.        ...
....       .d%¼J@[⌗ü⩩@"//>:⁖⁖.´⁖.. `..´´´  JJ`:⌗´         ..
...       ..⩩@@EP⌗e@@@¾¼<+e\⁖`..´.. ´..    d+\.\`.        ..
....       .@@@P>?eZ@@@@%Z+^:``.. .´.     ´/+¾´d`.        ..
...        .J@%>":/Z@@@%Y[^:⁖⁖.......      _¾Z⁖d\ .       ..
.. ..       /@@%¼¼eüZZZY+⌗?:⁖:⁖`´`´        ⁖%Z:/%`.\       .
....        ./¾⌗e>>7YY++⌗??v?v:⁖..         .@@¼:@\./`      .
..          ..J%Ze⌗e+++⌗⌗¼¼⌗⌗?:⁖⁖P`         Z@+:Z%`.\      .
..            ´Z@%+>>>>⌗⌗⌗⌗^?⁖⁖⁖⁖:?__vv¼¼:⁖.JZ+\J%`./`    ..
...            .´//^"³²¼¼¼\¼wa66⩩WEEPP*³‛`. d¾¾%?Z\.⁖v    ..
..             ..  .   .J6WHHMMP>³`´´..´´   /¾Z+\J¾.⁖/`  ...
.                     .dHMM@¾++⌗⁖`´         ´ZZ¾¾/+`´?\. ...
. .                  .⩩EP+Z%YY>^⁖´.          J@%Z\<\.\o\....
..   .              ./P+++++++¼?'´           dZ%Y>d¼:d%%:...
#>
function ConvertTo-AsciiArt {
    [Alias("asciiart", "aa")]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [String] $Path,

        [ValidateRange(4, 200)]
        [Alias("width", "mw", "w")]
        [int] $MaxWidth = 80,

        # Whether to match each ASCII character against a "full pixel" or four "subpixels". Subpixel comparison is much slower.
        [ValidateRange(0, 2)]
        [Alias("compare", "c", "p")]
        [BmpToAsciiType] $BmpToAsciiType = 0,

        # Ratio from 0 to 1. 0 matches on full-pixel brightness, and 1 on subpixel brightnesses.
        [ValidateRange(0, 1)]
        [Alias("shaping", "s")]
        [double] $BrightnessShapeRatio = 0.5,

        # The ratio of your font's height:width (including line height). Monospace fonts are typically ~2:1; with line spacing, ~2.2:1.
        [ValidateRange(0.5, 4)]
        [Alias("ratio", "r", "height", "h")]
        [double] $DisplayRatio = 2.2
    )

    # # DEPENDENCIES
    Add-Type -AssemblyName System.Drawing


    # # VARIABLES
    $subpixel_comparison = $BmpToAsciiType -gt 0
    $sp = $subpixel_comparison ? 1 : 0

    # Characters from darkest to lightest
    $characters = ' .,-:;◦+*@&H#$'.ToCharArray()
    $c = $characters.count

    # When SubpixelDepth is set to 1, each character is chosen from 4 pixels.
    # Characters are keyed with 4 brightness values (from 0 to 10 for human-being-reasons).
    # A character is chosen by 4 pixels (and their brightnesses) vs the char's brightnesses.
    # This list is a bit short of what's needed, which could be closer to 60 or 100 chars.
    $subchars = @{
        # These 4 values were set by pure vibes. They can be improved, esp. per-font.
        # tl, tr, bl, br
        # (top-left, top-right, bottom-left, bottom-right).
        (0, 0, 0, 0)         = ' '
        (0, 0, 2, 2)         = '.'
        (0, 0, 4, 4)         = '_'
        (0, 5, 7, 7)         = 'd'
        (1, 1, 4, 4)         = 'v'
        (1, 1, 8, 8)         = 'w'
        (1, 2, 1, 2)         = '⁖'
        (1, 3, 0, 0)         = '´'
        (1, 5, 5, 1)         = '/'
        (1, 7, 5, 7)         = 'J'
        # (2.2, 2.2, 2.2, 2.2) = '-'
        (2, 2, 2, 2)         = ':'
        (2, 2, 5, 5)         = 'o'
        (2, 6, 2, 6)         = '<'
        (2.8, 2.8, 0, 0)     = '‾'
        (3, 2, 0, 0)         = '`'
        (3, 3, 0, 0)         = "'"
        (3, 3, 3, 5)         = '¼'
        (3, 3, 4, 4)         = '⌗'
        (3, 3, 6, 6)         = 'e'
        (3, 3, 8, 8)         = 'a'
        (3, 4, 0, 0)         = '²'
        (3, 4, 1, 3)         = '?'
        (3, 7, 3, 7)         = ']'
        (4, 0, 6, 5)         = 'h'
        (4, 0, 7, 5)         = 'L'
        (4, 0, 7, 7)         = 'b'
        (4, 3, 0, 0)         = "`‛"
        (4, 4, 0, 0)         = '³'
        (4, 4, 7, 7)         = 'ü'
        (5, 1, 1, 5)         = '\'
        (5, 5, 0, 0)         = '"'
        (5, 5, 1, 1)         = '^'
        (5, 5, 5, 5)         = '+'
        (5, 7, 2, 6)         = '4'
        (5, 7, 7, 5)         = 'Z'
        (5, 8, 4, 3)         = '7'
        (6, 2, 6, 2)         = '>'
        (6, 3, 8, 8)         = '6'
        (6, 6, 0, 0)         = '*'
        (6, 6, 8, 8)         = '⩩'
        (6, 6, 10, 10)       = 'W'
        (6.5, 6.5, 4, 4)     = 'Y'
        (7, 3, 7, 3)         = '['
        (7, 4, 4, 7)         = '¾'
        (7, 5, 5, 7)         = '%'
        (7, 7, 7, 7)         = '@'
        (8, 8, 2, 4)         = '9'
        (8, 8, 8, 8)         = '&'
        (9, 6, 9, 6)         = 'E'
        (9, 9, 9, 9)         = 'H'
        (9, 8, 5, 1)         = 'P'
        (9.5, 9.5, 9.5, 9.5) = '#'
        (10, 10, 6, 6)       = 'M'
        (10, 10, 10, 10)     = '$'
    }
    
    # todo: program to print chars > bmp, resize bpm to NxN, and record results to tsv.
    #   Also needs to use a DisplayRatio. And probably reject chars that go outside of boundaries?
    #   File format:
    #    n = 16
    #    a\t0.0\t0.0\t0.0\t0.0 # order is from left to right, then top to bottom.

    
    # # FUNCTIONS

    function Get-NearestCharacterBySubpixel ($pix_bri, $char_dict, $ratio) {
        $average_pixel_brightness = $pix_bri | Measure-Object -Average | Select-Object -Expand Average
        $p = 0.80; $q = 1 - $p; # where p is the percent of correction to apply during shape fit.
        
        $distances = [hashtable]::new(0, [System.StringComparer]::Ordinal)
        foreach ($art_char in $char_dict.GetEnumerator()) {
            # Brightness fit is very straightforward.
            $average_char_brightness = $art_char.Name | Measure-Object -Average | Select-Object -Expand Average
            $b = [Math]::Pow(
                [Math]::Abs($average_pixel_brightness * 10 - $average_char_brightness),
                1.4 #?
            )

            # Shape coordinates are first corrected (by some %) toward the average pixel brightness.
            $pixels = $pix_bri | ForEach-Object { ($p / 4) * $average_pixel_brightness + (1 - $p / 4) * $_ } # tiniest nudge
            $coordinates = $art_char.Name | ForEach-Object { $p * $average_pixel_brightness * 10 + $q * $_ }

            # "$pixels | $coordinates" | oh
            # "p: {0} ({1}) | c: {2} => {3}" -f ($pix_bri -join ','), $average_pixel_brightness, ($art_char.Name -join ','), ($coordinates -join ',') | oh
            $s = 0.0d
            0..3 | ForEach-Object {
                $s += [Math]::Pow($coordinates[$_] - $pixels[$_] * 10, 2)
            }

            # The 'distance' is a metric of the fitness on both shape and brightness.
            $distances.Add($art_char.Value, $s * $ratio + $b * (1 - $ratio))
            # "`$b: $b | `$s: $s | `$total: $($s * $ratio + $b * (1 - $ratio))" | out-host
        }
        $distances.GetEnumerator() | Sort-Object Value | Select-Object -First 1 -ExpandProperty Name
    }


    # # PROCESS
    $image = [Drawing.Image]::FromFile($Path)

    # Redraw the image as a bitmap with new dimensions, stretched to the DisplayRatio.
    # When using subpixels (sp = 1), the bitmap dimensions are doubled.
    $bmp_width = $MaxWidth * [Math]::Pow(2, $sp)
    $h = ($image.Height / ($image.Width / $bmp_width) / $DisplayRatio)
    $bmp_height = ($h + 2 - 1 - (($h + 2 - 1) % 2)) # "if odd, round up to next even number"
    $bitmap = New-Object Drawing.Bitmap($image, $bmp_width, $bmp_height)
    $image.Dispose()
    if (!$bitmap) { throw 'bitmap is null' }

    # Use a string builder to store the characters.
    [System.Text.StringBuilder] $sb = ""

    #* Pixel comparison.
    if (!$subpixel_comparison) {
        # Evaluate each pixel's brightness.
        # Take each pixel line...
        for ([int]$y = 0; $y -lt $bitmap.Height; $y++) {
            # Take each pixel column...
            for ([int]$x = 0; $x -lt $bitmap.Width; $x++) {
                $color = $bitmap.GetPixel($x, $y)
                $brightness = $color.GetBrightness()
                [int]$offset = (1 - $brightness) * $c
                $ch = $characters[$offset] # sorted lightest => darkest
                if (-not $ch) { $ch = $characters[-1] }
                # Add character to line of text.
                $null = $sb.Append($ch)
            }
            # Start a new line.
            $null = $sb.AppendLine()
        }
    }
    #* Subpixel comparison.
    else {
        if ($BmpToAsciiType -eq [BmpToAsciiType]::PixelAndSubpixel) {
            # Add the full-pixel characters to the subpixel table, very sloppily, who cares.
            0..($c - 1) | ForEach-Object {
                $b = $_ / ($c - 1)
                $subchars.Add(($b, $b, $b, $b), $characters[$_])
            }
        }

        # Evaluate each 2x2 for its best-fitting character from $subchars.
        $pos = @((0, 0), (1, 0), (1, 0), (1, 1)) # tl, tr, bl, br
        $bri = [System.Collections.ArrayList] @()

        # Take every two pixel lines...
        for ($yy = 0; $yy -lt $bitmap.Height; $yy += 2) {
            # Take every two pixel columns...
            for ($xx = 0; $xx -lt $bitmap.Width; $xx += 2) {
                # Take a 2x2 of brightness values, using the (4x1) $pos order.
                $bri.Clear();
                0..3 | ForEach-Object {
                    $x = $xx + $pos[$_][0]
                    $y = $yy + $pos[$_][1]
                    $color = $bitmap.GetPixel($x, $y)
                    $bri.Add($color.GetBrightness()) | out-null
                }
                $ch = Get-NearestCharacterBySubpixel $bri $subchars $BrightnessShapeRatio
                if (-not $ch) { $ch = [char]' ' } # should prob allow a background fill
                $null = $sb.Append($ch)
            }
            $null = $sb.AppendLine()
        }
    }

    # Clean up and return.
    $bitmap.Dispose()


    # # EXIT
    return $sb.ToString()
}


# # ARGUMENT COMPLETION

$BmpToAscii = {
    param ($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameter)
    if ($wordToComplete -match '^\d+$') {
        # $Values = [BmpToAsciiType].GetEnumValues() # All our values are single-digit, so nbd
        return [BmpToAsciiType] [int] $wordToComplete[0]
    }
    else {
        $Fields = [BmpToAsciiType].GetEnumNames()
        $Phrase = '*', ($wordToComplete -replace '^[*\s]+|[*\s]+$', ''), '*' -join ''
        return $Fields | Where-Object { $_ -Like $Phrase } | Sort-Object
    }
}
Register-ArgumentCompleter -CommandName 'ConvertTo-AsciiArt' -ParameterName 'BmpToAsciiType' -ScriptBlock $BmpToAscii
