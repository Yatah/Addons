# The Goblin Ledger: the textures of its three themes -> art\ledger\*.tga (and a contact sheet
# ledger_sheet.png next to them when -Sheet is given). Run into a scratch folder first, compare,
# then copy:  build_ledger.ps1 -Out <folder> [-Sheet]
param([string]$Out = "", [switch]$Sheet)
$d = Split-Path -Parent $MyInvocation.MyCommand.Path
$hud = Join-Path (Split-Path -Parent $d) "hud"
if (-not $Out) { $Out = Split-Path -Parent (Split-Path -Parent $d) }
Add-Type -TypeDefinition (([IO.File]::ReadAllText("$hud\kit.cs")) + "`n" + ([IO.File]::ReadAllText("$d\ledger.cs"))) -ReferencedAssemblies System.Drawing
Add-Type -AssemblyName System.Drawing
$art = Join-Path $Out "art\ledger"
New-Item -ItemType Directory -Force $art | Out-Null
$made = [ordered]@{}
function Save($name, $img) { $img.SaveTga("$art\$name.tga"); $made[$name] = $img }

# themes: page, cover, metal, spine, tab, button (colours 0..1)
$themes = @(
	@{ k = "merchant"; page = { [LedgerArt]::Parchment(256, 0.94, 0.88, 0.73, 0.82, 0.70, 0.50, 11) }; cover = { [LedgerArt]::Leather(256, 0.38, 0.23, 0.13, 21) }
		metal = @(0.80, 0.63, 0.30); band = 0; corner = 0; spine = @(0.30, 0.18, 0.10); spineStyle = 0
		tab = @(0.13, 0.31, 0.19); tabStyle = 0; button = @(0.44, 0.28, 0.15); buttonStyle = 0 },
	@{ k = "bilgewater"; page = { [LedgerArt]::Plate(256, 0.21, 0.22, 0.21, 0.14, 0.24, 0.17, 31) }; cover = { [LedgerArt]::Plate(256, 0.10, 0.10, 0.10, 0.09, 0.15, 0.11, 41) }
		metal = @(0.74, 0.44, 0.25); band = 1; corner = 1; spine = @(0.20, 0.20, 0.20); spineStyle = 1
		tab = @(0.62, 0.36, 0.20); tabStyle = 1; button = @(0.22, 0.23, 0.22); buttonStyle = 1 },
	@{ k = "prince"; page = { [LedgerArt]::Parchment(256, 0.97, 0.94, 0.85, 0.88, 0.82, 0.67, 51) }; cover = { [LedgerArt]::Leather(256, 0.07, 0.23, 0.15, 61) }
		metal = @(0.88, 0.71, 0.32); band = 2; corner = 2; spine = @(0.06, 0.19, 0.12); spineStyle = 2
		tab = @(0.46, 0.10, 0.12); tabStyle = 2; button = @(0.10, 0.29, 0.19); buttonStyle = 0 }
)
$seed = 100
foreach ($t in $themes) {
	$k = $t.k; $m = $t.metal; $seed += 10
	Save "${k}_page" (& $t.page)
	Save "${k}_cover" (& $t.cover)
	$band = [LedgerArt]::Band(256, 32, $m[0], $m[1], $m[2], $t.band, $seed)
	Save "${k}_edge" $band
	# (the sides: the same band turned, its shadow on the inner side)
	Save "${k}_edgev" $band.Rot()
	Save "${k}_corner" ([LedgerArt]::Corner(64, 24, $m[0], $m[1], $m[2], $t.corner, $seed + 1))
	$s = $t.spine
	Save "${k}_spine" ([LedgerArt]::Spine(64, 256, $s[0], $s[1], $s[2], $m[0], $m[1], $m[2], $t.spineStyle, $seed + 2))
	$c = $t.tab
	Save "${k}_tab" ([LedgerArt]::Tab(128, 64, $c[0], $c[1], $c[2], $m[0], $m[1], $m[2], $t.tabStyle, $seed + 3))
	$b = $t.button
	Save "${k}_button" ([LedgerArt]::Button(128, 32, $b[0], $b[1], $b[2], $m[0], $m[1], $m[2], $t.buttonStyle, $seed + 4))
}
Save "stamp_verified" ([LedgerArt]::Stamp(256, 96, "VERIFIED", 7))
Save "stamp_review" ([LedgerArt]::Stamp(256, 96, "NEEDS REVIEW", 8))
Save "stamp_sold" ([LedgerArt]::Stamp(256, 96, "SOLD", 9))
Save "coin" ([LedgerArt]::Coin(64, 0.88, 0.70, 0.30, 5))
Save "rivet" ([LedgerArt]::RivetImg(16))
Save "flourish" ([LedgerArt]::Flourish(256, 16))
Save "dot" ([LedgerArt]::Dot(16))
Save "fade" ([LedgerArt]::Fade(16, 64, 0, 1))
"textures: $($made.Count) -> $art"

if ($Sheet) {
	# every texture on a mid grey and on a dark ground, scaled to fit 256 px cells
	$cols = 6; $cell = 264
	$rows = [Math]::Ceiling($made.Count / $cols)
	$bm = New-Object System.Drawing.Bitmap ($cols * $cell), ($rows * ($cell + 18))
	$g = [System.Drawing.Graphics]::FromImage($bm)
	$g.Clear([System.Drawing.Color]::FromArgb(255, 70, 66, 60))
	$font = New-Object System.Drawing.Font "Arial", 10
	$i = 0
	foreach ($name in $made.Keys) {
		$img = $made[$name]; $x = ($i % $cols) * $cell; $y = [Math]::Floor($i / $cols) * ($cell + 18)
		$k = [Math]::Min(1.0, [Math]::Min(256 / $img.W, 256 / $img.H))
		if ($img.W -le 64 -and $img.H -le 64) { $k = [Math]::Min(4, 256 / [Math]::Max($img.W, $img.H)) }
		$tile = $img.ToBitmap()
		$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
		$g.DrawImage($tile, [int]($x + 4), [int]($y + 4), [int]($img.W * $k), [int]($img.H * $k))
		$g.DrawString($name, $font, [System.Drawing.Brushes]::White, [float]($x + 4), [float]($y + $cell - 4))
		$tile.Dispose(); $i++
	}
	$bm.Save("$Out\ledger_sheet.png", [System.Drawing.Imaging.ImageFormat]::Png)
	"sheet: $Out\ledger_sheet.png"
}
