# Feature graphic v2 ("players"): logo left, physical Makapix player display + phone right.
# Output: distribution/screenshots/feature-graphic-players-1024x500.png
Add-Type -AssemblyName System.Drawing

$root = "C:\Users\fab\F\Estudo\Tecnologia\makapix-app"
$logoFile = "$root\distribution\logo\makapix-club-logo-2318p-transparent-bg.png"
$phoneShot = "$root\distribution\screenshots\phone\phone-02-artwork.png"
$outFile = "$root\distribution\screenshots\feature-graphic-players-1024x500-v2.png"

# --- logo content bbox (alpha threshold, sampled)
$logo = [System.Drawing.Bitmap]::new($logoFile)
$data = $logo.LockBits([System.Drawing.Rectangle]::new(0,0,$logo.Width,$logo.Height),
    [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
    [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$bytes = [byte[]]::new($data.Stride * $data.Height)
[System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)
$logo.UnlockBits($data)
$minX = $logo.Width; $minY = $logo.Height; $maxX = 0; $maxY = 0
for ($y = 0; $y -lt $logo.Height; $y += 4) {
    $row = $y * $data.Stride
    for ($x = 0; $x -lt $logo.Width; $x += 4) {
        if ($bytes[$row + $x*4 + 3] -gt 25) {
            if ($x -lt $minX) { $minX = $x }; if ($x -gt $maxX) { $maxX = $x }
            if ($y -lt $minY) { $minY = $y }; if ($y -gt $maxY) { $maxY = $y }
        }
    }
}
$pad = 12
$minX = [Math]::Max(0, $minX - $pad); $minY = [Math]::Max(0, $minY - $pad)
$maxX = [Math]::Min($logo.Width - 1, $maxX + $pad); $maxY = [Math]::Min($logo.Height - 1, $maxY + $pad)
$logoSrc = [System.Drawing.Rectangle]::new($minX, $minY, $maxX - $minX + 1, $maxY - $minY + 1)

# --- the artwork shown on the player: square crop of the house from the phone detail shot
# 02-artwork.png is 1344x2688, cropped 232px from the top of the raw capture; in it the
# artwork square spans roughly x 40..1303, y 341..1604.
$detail = [System.Drawing.Bitmap]::new($phoneShot)
$artSrc = [System.Drawing.Rectangle]::new(40, 341, 1263, 1263)

$W = 1024; $H = 500
$bmp = [System.Drawing.Bitmap]::new($W, $H)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

# background
$bgBrush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
    [System.Drawing.Point]::new(0,0), [System.Drawing.Point]::new($W,$H),
    [System.Drawing.Color]::FromArgb(255, 18, 22, 38),
    [System.Drawing.Color]::FromArgb(255, 6, 8, 14))
$g.FillRectangle($bgBrush, 0, 0, $W, $H)

$palette = @(
    @(91,127,232), @(232,132,60), @(124,193,68), @(78,201,196),
    @(217,79,79), @(226,222,120), @(154,104,214)
)

# sparse pixel accents (left/top only; right side stays calm)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None
$squares = @(
    @(440, 44, 24, 0, 65), @(180, 40, 22, 5, 50), @(90, 60, 16, 1, 60),
    @(50, 420, 28, 4, 45), @(120, 350, 18, 6, 40), @(300, 430, 20, 2, 50),
    @(470, 330, 16, 3, 55)
)
foreach ($s in $squares) {
    $c = $palette[$s[3]]
    $br = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb($s[4], $c[0], $c[1], $c[2]))
    $g.FillRectangle($br, $s[0], $s[1], $s[2], $s[2])
    $br.Dispose()
}
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

function New-RoundedPath([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
    $p = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $p.AddArc($x, $y, 2*$r, 2*$r, 180, 90)
    $p.AddArc($x+$w-2*$r, $y, 2*$r, 2*$r, 270, 90)
    $p.AddArc($x+$w-2*$r, $y+$h-2*$r, 2*$r, 2*$r, 0, 90)
    $p.AddArc($x, $y+$h-2*$r, 2*$r, 2*$r, 90, 90)
    $p.CloseFigure()
    return $p
}

# --- the physical player: bezelled square display, wall-hung feel (glow + drop shadow)
$dispCX = 665.0; $dispCY = 215.0; $dispSize = 270.0
$dx = $dispCX - $dispSize/2; $dy = $dispCY - $dispSize/2

# ambient glow behind the device
for ($i = 3; $i -ge 1; $i--) {
    $grow = 14.0 * $i
    $glowPath = New-RoundedPath ($dx - $grow) ($dy - $grow) ($dispSize + 2*$grow) ($dispSize + 2*$grow) (3 + $grow)
    $glowBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(10, 137, 168, 245))
    $g.FillPath($glowBrush, $glowPath); $glowBrush.Dispose(); $glowPath.Dispose()
}
# drop shadow
$shPath = New-RoundedPath ($dx + 8) ($dy + 14) $dispSize $dispSize 3
$shBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(120, 0, 0, 0))
$g.FillPath($shBrush, $shPath); $shBrush.Dispose(); $shPath.Dispose()
# bezel
$bezPath = New-RoundedPath $dx $dy $dispSize $dispSize 3
$bezBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 22, 25, 33))
$g.FillPath($bezBrush, $bezPath); $bezBrush.Dispose()
$bezPen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(255, 255, 255, 255), 3)
$g.DrawPath($bezPen, $bezPath); $bezPen.Dispose(); $bezPath.Dispose()
# screen (the artwork), inset inside the bezel
$inset = 16.0
$scrPath = New-RoundedPath ($dx + $inset) ($dy + $inset) ($dispSize - 2*$inset) ($dispSize - 2*$inset) 3
$state = $g.Save()
$g.SetClip($scrPath)
$g.DrawImage($detail,
    [System.Drawing.RectangleF]::new($dx + $inset, $dy + $inset, $dispSize - 2*$inset, $dispSize - 2*$inset),
    $artSrc, [System.Drawing.GraphicsUnit]::Pixel)
$g.Restore($state)
$scrPen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(255, 10, 12, 16), 2)
$g.DrawPath($scrPen, $scrPath); $scrPen.Dispose(); $scrPath.Dispose()

# --- the phone (02-artwork.png with the live player bar), lower right, slight tilt
$phCX = 900.0; $phCY = 316.0; $phW = 195.0; $phTilt = 8.0
$img = $detail
$phH = $phW * $img.Height / $img.Width
$g.TranslateTransform($phCX, $phCY)
$g.RotateTransform($phTilt)
$x = -$phW/2; $y = -$phH/2
$shPath = New-RoundedPath ($x+6) ($y+10) $phW $phH 18
$shBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(110, 0, 0, 0))
$g.FillPath($shBrush, $shPath); $shBrush.Dispose(); $shPath.Dispose()
$clipPath = New-RoundedPath $x $y $phW $phH 18
$state = $g.Save()
$g.SetClip($clipPath)
$g.DrawImage($img, $x, $y, $phW, $phH)
$g.Restore($state)
$pen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(255, 58, 66, 86), 2.5)
$g.DrawPath($pen, $clipPath); $pen.Dispose(); $clipPath.Dispose()
$g.ResetTransform()

# --- pixel "cast beam" from phone toward the display
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None
$beam = @( @(856, 112, 13), @(826, 94, 10), @(801, 80, 8) )
foreach ($b in $beam) {
    $br = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(230, 137, 168, 245))
    $g.FillRectangle($br, $b[0], $b[1], $b[2], $b[2])
    $br.Dispose()
}
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

# --- left column: logo + taglines + palette strip
$cx = 245.0
$logoW = 350.0
$logoH = $logoW * $logoSrc.Height / $logoSrc.Width
if ($logoH -gt 300) { $logoH = 300.0; $logoW = $logoH * $logoSrc.Width / $logoSrc.Height }
$destRect = [System.Drawing.RectangleF]::new($cx - $logoW/2, 42, $logoW, $logoH)
$g.DrawImage($logo, $destRect, $logoSrc, [System.Drawing.GraphicsUnit]::Pixel)

$fTag = [System.Drawing.Font]::new("Segoe UI", 25, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$white = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 240, 244, 252))
$grey  = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 148, 158, 178))
$fmt = [System.Drawing.StringFormat]::new()
$fmt.Alignment = [System.Drawing.StringAlignment]::Center
$tagY = 42 + $logoH + 22
$g.DrawString("Pixel art on real displays.", $fTag, $white, $cx, $tagY, $fmt)
$g.DrawString("Sync the club to Makapix players.", $fTag, $grey, $cx, $tagY + 34, $fmt)

$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None
$stripW = 7*30 - 8
$px = [int]($cx - $stripW/2); $py = [int]($tagY + 88)
for ($i = 0; $i -lt 7; $i++) {
    $c = $palette[$i]
    $br = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, $c[0], $c[1], $c[2]))
    $g.FillRectangle($br, $px + $i*30, $py, 22, 22)
    $br.Dispose()
}

$fTag.Dispose(); $white.Dispose(); $grey.Dispose(); $fmt.Dispose()
$g.Dispose(); $logo.Dispose(); $detail.Dispose()

$final = $bmp.Clone([System.Drawing.Rectangle]::new(0,0,$W,$H), [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$final.Save($outFile, [System.Drawing.Imaging.ImageFormat]::Png)
$final.Dispose(); $bmp.Dispose()
"saved: $outFile"
