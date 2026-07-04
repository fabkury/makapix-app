Add-Type -AssemblyName System.Drawing

$shots = "C:\Users\fab\F\Estudo\Tecnologia\makapix-app\distribution\screenshots\phone"
$logoFile = "C:\Users\fab\F\Estudo\Tecnologia\makapix-app\distribution\logo\makapix-club-logo-2318p-transparent-bg.png"
$outFile = "C:\Users\fab\F\Estudo\Tecnologia\makapix-app\distribution\screenshots\feature-graphic-1024x500.png"

# --- load logo and find its content bounding box (alpha threshold, sampled grid)
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
$srcRect = [System.Drawing.Rectangle]::new($minX, $minY, $maxX - $minX + 1, $maxY - $minY + 1)
"logo content: $($srcRect.Width)x$($srcRect.Height) at ($minX,$minY)"

$W = 1024; $H = 500
$bmp = [System.Drawing.Bitmap]::new($W, $H)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

# --- background: deep navy -> black diagonal gradient
$bgBrush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
    [System.Drawing.Point]::new(0,0), [System.Drawing.Point]::new($W,$H),
    [System.Drawing.Color]::FromArgb(255, 18, 22, 38),
    [System.Drawing.Color]::FromArgb(255, 6, 8, 14))
$g.FillRectangle($bgBrush, 0, 0, $W, $H)

# --- pixel-square accents (crisp, no AA), editor palette colours, low alpha
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None
$palette = @(
    @(91,127,232), @(232,132,60), @(124,193,68), @(78,201,196),
    @(217,79,79), @(226,222,120), @(154,104,214)
)
$squares = @(
    @(430, 40, 26, 0, 70), @(480, 430, 34, 1, 60), @(400, 300, 18, 2, 55),
    @(560, 30, 20, 3, 65), @(50, 420, 28, 4, 45), @(180, 40, 22, 5, 50),
    @(340, 90, 30, 6, 45), @(300, 420, 22, 0, 55), @(90, 60, 16, 1, 60),
    @(250, 330, 14, 3, 50), @(390, 180, 12, 4, 60), @(120, 350, 18, 6, 40)
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

# --- screenshot cards, fanned on the right
$cards = @(
    @("phone-01-feed-v2.png", 640, 330, 190, -9),
    @("phone-03-editor.png",  955, 330, 190,  9),
    @("phone-02-artwork.png", 795, 300, 210,  0)
)
foreach ($cardDef in $cards) {
    $img = [System.Drawing.Bitmap]::new("$shots\$($cardDef[0])")
    $cw = [float]$cardDef[3]
    $ch = $cw * $img.Height / $img.Width
    $g.TranslateTransform($cardDef[1], $cardDef[2])
    $g.RotateTransform($cardDef[4])
    $x = -$cw/2; $y = -$ch/2

    $shPath = New-RoundedPath ($x+6) ($y+10) $cw $ch 18
    $shBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(110, 0, 0, 0))
    $g.FillPath($shBrush, $shPath); $shBrush.Dispose(); $shPath.Dispose()

    $clipPath = New-RoundedPath $x $y $cw $ch 18
    $state = $g.Save()
    $g.SetClip($clipPath)
    $g.DrawImage($img, $x, $y, $cw, $ch)
    $g.Restore($state)

    $pen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(255, 58, 66, 86), 2.5)
    $g.DrawPath($pen, $clipPath)
    $pen.Dispose(); $clipPath.Dispose()
    $g.ResetTransform()
    $img.Dispose()
}

# --- left column: logo + taglines + palette strip, centred on cx
$cx = 245.0
$logoW = 350.0
$logoH = $logoW * $srcRect.Height / $srcRect.Width
if ($logoH -gt 300) { $logoH = 300.0; $logoW = $logoH * $srcRect.Width / $srcRect.Height }
$destRect = [System.Drawing.RectangleF]::new($cx - $logoW/2, 42, $logoW, $logoH)
$g.DrawImage($logo, $destRect, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)

$fTag = [System.Drawing.Font]::new("Segoe UI", 25, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$white = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 240, 244, 252))
$grey  = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 148, 158, 178))
$fmt = [System.Drawing.StringFormat]::new()
$fmt.Alignment = [System.Drawing.StringAlignment]::Center

$tagY = 42 + $logoH + 22
$g.DrawString("Animated pixel art.", $fTag, $white, $cx, $tagY, $fmt)
$g.DrawString("Draw it. Share it. Remix it.", $fTag, $grey, $cx, $tagY + 34, $fmt)

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
$g.Dispose(); $logo.Dispose()

$final = $bmp.Clone([System.Drawing.Rectangle]::new(0,0,$W,$H), [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$final.Save($outFile, [System.Drawing.Imaging.ImageFormat]::Png)
$final.Dispose(); $bmp.Dispose()
"saved: $outFile"
