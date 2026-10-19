<#
    pick-theme-colors.ps1 -- suggest a SevenWork image-theme palette from a wallpaper.

    Usage:
        powershell -NoProfile -ExecutionPolicy Bypass -File tools\pick-theme-colors.ps1 `
            -Image "D:\Pictures\your-wall.png" [-Name "MyTheme"]

    Why: the shipped backdrop-image theme gets its colours from the image itself
    (its mean colour), so the window chrome and the editor sink into the picture
    instead of forming a visible rectangle. This script does that measurement for
    you.

    It reports the sampled luma distribution and prints a ready-to-paste
    ThemeService.Themes entry.

    NOTE: keep this file pure ASCII. powershell.exe 5.1 reads .ps1 as system ANSI
    (GBK here); non-ASCII would corrupt it and can swallow the following quote.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Image,

    [string]$Name = "MyTheme"
)

Add-Type -AssemblyName System.Drawing

if (-not (Test-Path -LiteralPath $Image)) {
    Write-Error ("image not found: " + $Image)
    exit 1
}

# -- sample the image down to 256 px wide first -------------------------------
# the source may be 9M+ pixels; GetPixel on all of them in PowerShell is slow,
# and the mean/dark/light statistics do not change after such a reduction.
$src = [System.Drawing.Image]::FromFile($Image)
$sw = $src.Width
$sh = $src.Height
$tw = 256
$th = [Math]::Max(1, [int][Math]::Round($sh * $tw / $sw))
$smp = New-Object -TypeName System.Drawing.Bitmap -ArgumentList @($tw, $th)
$gfx = [System.Drawing.Graphics]::FromImage($smp)
$gfx.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$gfx.DrawImage($src, 0, 0, $tw, $th)
$gfx.Dispose()
$src.Dispose()

# -- walk every sampled pixel -------------------------------------------------
$lum = New-Object -TypeName 'System.Collections.Generic.List[double]'
$sr = 0.0
$sg = 0.0
$sb = 0.0
for ($y = 0; $y -lt $th; $y++) {
    for ($x = 0; $x -lt $tw; $x++) {
        $c = $smp.GetPixel($x, $y)
        $sr += $c.R
        $sg += $c.G
        $sb += $c.B
        $lum.Add((0.299 * $c.R + 0.587 * $c.G + 0.114 * $c.B))
    }
}
$smp.Dispose()

$n = $lum.Count
$mR = [int][Math]::Round($sr / $n)
$mG = [int][Math]::Round($sg / $n)
$mB = [int][Math]::Round($sb / $n)
$meanLuma = 0.299 * $mR + 0.587 * $mG + 0.114 * $mB

$sorted = $lum.ToArray()
[Array]::Sort($sorted)
$p10 = $sorted[[int]($n * 0.10)]
$p50 = $sorted[[int]($n * 0.50)]
$p90 = $sorted[[int]($n * 0.90)]

# -- suggested palette --------------------------------------------------------
# win / edBg : the mean colour pulled down to 0.55. This is the formula the
#              shipped backdrop-image theme uses -- mean #181C25 -> win #0D0F14.
#              Both are set to the same value so the editor area and the window
#              chrome read as one surface (no rectangle of a different shade).
$k = 0.55
$wR = [int][Math]::Max(0, [Math]::Min(255, [Math]::Round($mR * $k)))
$wG = [int][Math]::Max(0, [Math]::Min(255, [Math]::Round($mG * $k)))
$wB = [int][Math]::Max(0, [Math]::Min(255, [Math]::Round($mB * $k)))
$win = ("{0:X2}{1:X2}{2:X2}" -f $wR, $wG, $wB)

# text / dim : near-white. A bright image cannot carry light text unless it is
#             dimmed with bgAlpha, so flip the foreground dark in that case.
$bright = ($meanLuma -gt 90)
$text = if ($bright) { "1A1C22" } else { "F5F9FF" }
$dim = if ($bright) { "5A6068" } else { "9FAABC" }
$alpha = if ($bright) { 30 } else { 0 }

$aspect = [Math]::Round($sw / $sh, 2)

# -- report ------------------------------------------------------------------
Write-Output ("image       : " + $Image)
Write-Output ("size        : {0} x {1}   aspect {2}" -f $sw, $sh, $aspect)
Write-Output ("sampled     : {0} x {1}   ({2} px)" -f $tw, $th, $n)
Write-Output ("mean colour : #{0:X2}{1:X2}{2:X2}   luma {3:N1}" -f $mR, $mG, $mB, $meanLuma)
Write-Output ("luma p10/p50/p90 : {0:N1} / {1:N1} / {2:N1}" -f $p10, $p50, $p90)
Write-Output ""

if ($aspect -gt 1.15) {
    Write-Output "crop note   : wider than the editor area -> cover scaling trims the"
    Write-Output "              left/right edges. Keep the subject near the centre."
} elseif ($aspect -lt 0.75) {
    Write-Output "crop note   : taller than the editor area -> cover scaling trims the"
    Write-Output "              top/bottom edges. Keep the subject near the centre."
} else {
    Write-Output "crop note   : close to the editor aspect ratio, almost nothing is trimmed."
}

if ($bright) {
    Write-Output "darkness    : the image is BRIGHT -> bgAlpha 30 is suggested, and the"
    Write-Output "              foreground is switched to dark. Verify the text still reads."
} else {
    Write-Output "darkness    : the image is DARK -> bgAlpha 0 (no dimming), matching"
    Write-Output "              Windows Terminal with backgroundImageOpacity set to 1."
}
Write-Output ""
Write-Output "Paste into ThemeService.Themes:"
Write-Output ""
Write-Output ("    {name: `"" + $Name + "`", win: `"" + $win + "`", edBg: `"" + $win + "`", text: `"" + $text + "`", dim: `"" + $dim + "`"")
Write-Output ("        , bg: `"" + $Image + "`"")
Write-Output ("        , bgAlpha: " + $alpha + "}")
