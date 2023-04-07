function ConvertTo-TextArt {
    [CmdletBinding()] param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [string] $Path,

        [Parameter(Mandatory, ParameterSetName = 'Fixed-Width')]
        [int] $Width,
        [Parameter(Mandatory, ParameterSetName = 'Fixed-Height')]
        [int] $Height,

        [Parameter()]
        [ValidateRange(0.5, 3)]
        [Alias('AspectRatio')]
        [double] $FontAspectRatio = 2,

        [ValidateRange(0, 1)]
        [double] $Smoothing = 0,

        [Parameter()]
        [hashtable] $CharacterLuminosityMap
    )

    $CharacterLuminosityMap ??= Get-CharacterLuminosityMap -Ascii -FontAspectRatio $FontAspectRatio -Normalize
    $script:distances = [hashtable]::new(0, [System.StringComparer]::Ordinal)

    # # FUNCTIONS

    function Get-BestCharacterForPixelQuad {
        [OutputType([char])]
        [CmdletBinding()] param (
            [Parameter(Mandatory)] [System.Collections.ArrayList] $Brightnesses
        )
        $averageBrightness = ($Brightnesses | Measure-Object -Average).Average
        $CharacterLuminosityMap.Keys | ForEach-Object {
            $averageCharBrightness = ($CharacterLuminosityMap[$_] | Measure-Object -Average).Average
            # $script:distances[$_] = Measure-SumSquareDifference (
            $script:distances[$_] = Measure-SumSquareDifference ($Brightnesses + ($averageBrightness * $Smoothing)) ($CharacterLuminosityMap[$_] + ($averageCharBrightness * $Smoothing))
        }
        return $script:distances.GetEnumerator() | Sort-Object Value | Select-Object -First 1 -Expand Name
    }

    function Measure-SumSquareDifference {
        [OutputType([double])] param($one, $two)
        $residuals = for ($ii = 0; $ii -lt 4; $ii++) { $two[$ii] - $one[$ii] }
        $sum = ($residuals | Measure-Object -Sum).Sum
        return $sum * $sum - ($residuals | % { $_ * $_ } | Measure-Object -Sum).Sum
    }

    # # PROCESS

    # Load the image and resize it as a bitmap.
    $image = [drawing.image]::FromFile($Path)
    if ($PSCmdlet.ParameterSetName -eq 'Fixed-Width') {
        $bitmapWidth = 2 * $Width
        $bitmapHeight = 2 * [System.Math]::Ceiling($bitmapWidth * ($image.Height / $image.Width) / $FontAspectRatio / 2)
    }
    if ($PSCmdlet.ParameterSetName -eq 'Fixed-Height') {
        $bitmapHeight = 2 * $Height
        $bitmapWidth = 2 * [System.Math]::Ceiling($bitmapHeight * ($image.Width / $image.Height) * $FontAspectRatio / 2)
    }
    $bitmap = New-Object Drawing.Bitmap($image, $bitmapWidth, $bitmapHeight)
    $image.Dispose()

    # Construct the string iteratively -- we only know its exact dimensions iff no glyphs are used.
    [System.Text.StringBuilder] $string = ''

    # Every character is mapped to a 2-by-2 pixel "quad"
    $quad = (0, 0), (0, 1), (1, 0), (1, 1)
    for ($yy = 0; $yy -lt $bitmapHeight; $yy += 2) {
        for ($xx = 0; $xx -lt $bitmapWidth; $xx += 2) {
            $null = $string.Append(
                $(
                    Get-BestCharacterForPixelQuad -Brightnesses (
                        $quad | ForEach-Object {
                            $bitmap.GetPixel(($xx + $_[0]), ($yy + $_[1])).GetBrightness()
                        }
                    )
                )
            )
        }
        # End each row with a newline character.
        $null = $string.AppendLine()
    }
    $bitmap.Dispose()
    return $string.ToString()
}


function Get-CharacterLuminosityMap {
    [CmdletBinding()] param(
        [Parameter(ParameterSetName = 'ASCII', Mandatory)]
        [switch] $Ascii,

        [Parameter(ParameterSetName = 'UTF-8', Mandatory)]
        [switch] $Unicode,        
        [Parameter(ParameterSetName = 'UTF-8', Mandatory)]
        [char[]] $Characters,
        
        [string] $Font = 'Consolas',

        [Alias('AspectRatio')]
        [ValidateRange(0.5, 3)]
        [double] $FontAspectRatio = 2,

        [switch] $Normalize,

        [switch] $SaveArtifacts
    )

    # Use at least the generally-accepted ASCII character range.
    $Characters ??= [char]32..[char]126

    # Set a reasonably large render -- needs to be big enough to overcome aliasing minutiae.
    $Width = 32
    $Height = [int]($Width * $FontAspectRatio)

    # Create a bitmap to render the characters
    $bmp = New-Object System.Drawing.Bitmap $Width, $Height

    # Create a graphics object to draw on the bitmap
    $g = [System.Drawing.Graphics]::FromImage($bmp)

    # Set the font and color (white for maximum luminosity)
    [System.Drawing.Font]$font = [System.Drawing.Font]::new($Font, $Height, [System.Drawing.GraphicsUnit]::Pixel)
    $brush = [System.Drawing.Brushes]::White

    # Create the text format and alignment
    $format = New-Object System.Drawing.StringFormat
    $format.FormatFlags = [System.Drawing.StringFormatFlags]::NoClip
    $format.Alignment = [System.Drawing.StringAlignment]::Center
    $format.LineAlignment = [System.Drawing.StringAlignment]::Center

    # Create a brightness map
    $brightnessMap = [ordered]@{}
    $coordinates = (0, 0), (0, 1), (1, 0), (1, 1)
    
    # Create a 2x2 bitmap and graphics object, each configured for maximum image quality
    $smallBmp = New-Object System.Drawing.Bitmap 2, 2
    $smallBmp.SetResolution($bmp.HorizontalResolution, $bmp.VerticalResolution)

    $smallG = [System.Drawing.Graphics]::FromImage($smallBmp)
    $smallG.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $smallG.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $smallG.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $smallG.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $smallG.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

    # Render each character
    foreach ($char in $Characters) {
        # Reset the image to black
        $g.Clear([System.Drawing.Color]::Black)
        
        # Draw the character in white
        $g.DrawString($char, $font, $brush, $Width / 2, $Height / 2, $format)

        # Copy the character from the large bitmap to the 2x2 bitmap
        $smallG.DrawImage($bmp, 0, 0, 2, 2)
        
        # Get the brightness values
        $brightnessMap[$char] = $coordinates | ForEach-Object {
            $smallBmp.GetPixel($_[0], $_[1]).GetBrightness()
        }

        if ($SaveArtifacts) {
            try {
                $invalid = [System.IO.Path]::GetInvalidFileNameChars() -join ''
                $invalid = "[$([regex]::Escape($invalid))]"
                # Saving to stream first establishes the media's MimeType and simplifies things
                $memoryStream = [System.IO.MemoryStream]::new()
                $bmp.Save($memoryStream, [System.Drawing.Imaging.ImageFormat]::Bmp)
                $image = [System.Drawing.Image]::FromStream($memoryStream)
                $path = "$env:USERPROFILE\artifact-$char.bmp" -replace $invalid, ([string][int]$char)
                $image.Save($path)
            }
            finally {
                Write-Host "Artifacts saved to: '$env:USERPROFILE\artifact-*.bmp'"
                $memoryStream.Dispose()
                $image.Dispose()
            }
        }
    }

    # Dispose our bitmap and graphics objects
    $bmp, $g, $smallBmp, $smallG | ForEach-Object Dispose -EA 0

    # Brightness normalization distorts the accuracy of the map in exchange for improving its discrimination.
    if ($PSBoundParameters['Normalize']) {
        # The maps are in 2D coordinates, so we just take their extrema twice, nbd:
        $min = (($brightnessMap.Values | ForEach-Object { $_ | Measure-Object -Minimum }).Minimum | Measure-Object -Minimum).Minimum
        $max = (($brightnessMap.Values | ForEach-Object { $_ | Measure-Object -Maximum }).Maximum | Measure-Object -Maximum).Maximum
        $ran = $max - $min

        $normalizeMap = [ordered]@{}
        foreach ($char in $brightnessMap.Keys) {
            $normalizeMap[$char] = $brightnessMap[$char] | ForEach-Object { ($_ - $min) / $ran }
        }
        $brightnessMap = $normalizeMap
    }

    # Return the brightness map
    return $brightnessMap
}
