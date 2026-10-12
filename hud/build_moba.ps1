# In-game art of the "moba" theme, modern retail dress (mockup v7-moba-modern): the pieces of the
# current WoW HUD (tools\hud\hud\*.png, cut at the exact UiTextureAtlasMember rects, 2x = 1 texel
# per px at 1440p) assembled at the v5 places. 3440 x 500 at the bottom of a 3440 x 1440 screen.
#   main          fixed decor (panels, empty slots, troughs)                 -> blocks\back*
#   other layers  pieces over / under something that moves, or shown with a unit -> atlas blocks\front
#   castfill, castchan, castfail, castshield                                  -> cast bar fills
# Geometry for the game in MobaGeom.lua (art px, origin bottom left of the screen).
param([string]$Out = "")
$d = Split-Path -Parent $MyInvocation.MyCommand.Path; if (-not $Out) { $Out = Split-Path -Parent (Split-Path -Parent $d) }
Add-Type -TypeDefinition (([IO.File]::ReadAllText("$d\kit.cs")) + "`n" + ([IO.File]::ReadAllText("$d\kit2.cs")) + "`n" + ([IO.File]::ReadAllText("$d\kit3.cs")) + "`n" + ([IO.File]::ReadAllText("$d\holes.cs"))) -ReferencedAssemblies System.Drawing
Add-Type -AssemblyName System.Drawing
$W = 3440; $SCR = 1440; $YO = 940; $H = $SCR - $YO
$HK = @{}; Get-ChildItem "$d\hud\*.png" | % { $HK[$_.BaseName] = [Img]::Load($_.FullName) }
$cpt = [Img]::Load("$d\COMBOPOINT.PNG")

# ---- layers (3440 x 500; screen y -> y - 940)
$layers = [ordered]@{ main = (New-Object Img $W, $H) }
$script:C = $layers.main
function Layer($n) { if (-not $layers.Contains($n)) { $layers[$n] = New-Object Img $W, $H }; $script:C = $layers[$n] }
function Put($img, $x, $y) { [K2]::Put($script:C, $img, [int]$x, [int]($y - $YO)) }
function Blit($img, $sx, $sy, $w, $h, $x, $y) { [K2]::Blit($script:C, $img, $sx, $sy, $w, $h, [int]$x, [int]($y - $YO)) }
function Rect($x, $y, $w, $h, $r, $g, $b, $a) { [K3]::Rect($script:C, [int]$x, [int]($y - $YO), [int]$w, [int]$h, $r, $g, $b, $a) }
function TileX($img, $x0, $x1, $y) { for ($x = $x0; $x -lt $x1; $x += $img.W) { Blit $img 0 0 ([Math]::Min($img.W, $x1 - $x)) $img.H $x $y } }
function TileY($img, $x, $y0, $y1) { for ($y = $y0; $y -lt $y1; $y += $img.H) { Blit $img 0 0 $img.W ([Math]::Min($img.H, $y1 - $y)) $x $y } }
# HUD panel: dark translucent inside, the thin modern frame (ui-hud-actionbar-frame-nineslice-2x)
function PanelFrame($w, $h) {
	$fr = New-Object Img $w, $h
	for ($xx = 34; $xx -lt $w - 44; $xx += 32) { $ww = [Math]::Min(32, $w - 44 - $xx); [K2]::Blit($fr, $HK.t, 0, 0, $ww, 32, $xx, 0); [K2]::Blit($fr, $HK.b, 0, 0, $ww, 46, $xx, $h - 46) }
	for ($yy = 32; $yy -lt $h - 46; $yy += 32) { $hh = [Math]::Min(32, $h - 46 - $yy); [K2]::Blit($fr, $HK.l, 0, 0, 34, $hh, 0, $yy); [K2]::Blit($fr, $HK.r, 0, 0, 44, $hh, $w - 44, $yy) }
	[K2]::Put($fr, $HK.tl, 0, 0); [K2]::Put($fr, $HK.tr, $w - 44, 0); [K2]::Put($fr, $HK.bl, 0, $h - 46); [K2]::Put($fr, $HK.br, $w - 44, $h - 46)
	return $fr
}
function Panel($x, $y, $w, $h, $alpha = 0.78) {
	# the frame alone, then its inside (flood from the outside stopped by the line: the fill
	# follows the chamfered corners), the fill under the frame
	$fr = PanelFrame $w $h
	$in = [Inside]::Fill($fr, 0.3, 0.045, 0.042, 0.04, 0.025, 0.022, 0.02, $alpha)
	Put $in $x $y; Put $fr $x $y
}# button of icon size $sz: the slot (under) / the frame (over, in another layer)
function Slot($x, $y, $sz) { $s = [int][Math]::Round($sz * 64 / 45); $o = [int](($s - $sz) / 2); Put ($HK.slot.Resize($s, [int]($s * 124 / 128))) ($x - $o) ($y - $o) }
function IconFrame($x, $y, $sz) { $f = [int][Math]::Round($sz * 46 / 45); Put ($HK.frame.Resize($f, [int]($f * 90 / 92))) ($x - 1) $y }
# the same for a $w x $h button (the key ring: not square)
function SlotWH($x, $y, $w, $h) { $sw = [int][Math]::Round($w * 64 / 45); $sh = [int][Math]::Round($h * 64 / 45); Put ($HK.slot.Resize($sw, [int]($sh * 124 / 128))) ($x - [int](($sw - $w) / 2)) ($y - [int](($sh - $h) / 2)) }
function IconFrameWH($x, $y, $w, $h) { $fw = [int][Math]::Round($w * 46 / 45); Put ($HK.frame.Resize($fw, [int][Math]::Round($h * 46 / 45 * 90 / 92))) ($x - 1) $y }
# three-slice: caps kept, middle stretched, height scaled to $h
function H3($img, $cl, $cr, $x, $y, $w, $h) {
	$k = $h / $img.H; $im = if ($k -ne 1) { $img.Resize([int][Math]::Round($img.W * $k), [int]$h) } else { $img }; $cl = [int]($cl * $k); $cr = [int]($cr * $k)
	Blit $im 0 0 $cl $h $x $y; Blit $im ($im.W - $cr) 0 $cr $h ($x + $w - $cr) $y
	Put ($im.Crop($cl, 0, $im.W - $cl - $cr, $h).Resize([int]($w - $cl - $cr), [int]$h)) ($x + $cl) $y
}
# the same three-slice on an image of its own ($w long, $h thick)
function H3Img($img, $cl, $cr, $w, $h) {
	$out = New-Object Img $w, $h; $k = $h / $img.H; $im = if ($k -ne 1) { $img.Resize([int][Math]::Round($img.W * $k), [int]$h) } else { $img }; $cl = [int]($cl * $k); $cr = [int]($cr * $k)
	[K2]::Blit($out, $im, 0, 0, $cl, $h, 0, 0); [K2]::Blit($out, $im, $im.W - $cr, 0, $cr, $h, $w - $cr, 0)
	[K2]::Put($out, $im.Crop($cl, 0, $im.W - $cl - $cr, $h).Resize([int]($w - $cl - $cr), [int]$h), $cl, 0); return $out
}
# an image turned a quarter clockwise (a horizontal bar standing up)
function Rot90($img) {
	$o = New-Object Img $img.H, $img.W
	for ($y = 0; $y -lt $img.H; $y++) { for ($x = 0; $x -lt $img.W; $x++) { $s = $img.I($x, $y); $q = $o.I($img.H - 1 - $y, $x); $o.R[$q] = $img.R[$s]; $o.G[$q] = $img.G[$s]; $o.B[$q] = $img.B[$s]; $o.A[$q] = $img.A[$s] } }
	return $o
}
function Disc($cx, $cy, $dd, $r, $g, $b) { $p = New-Object Img $dd, $dd; for ($j = 0; $j -lt $dd; $j++) { for ($i = 0; $i -lt $dd; $i++) { $dx = $i - $dd / 2 + 0.5; $dy = $j - $dd / 2 + 0.5; $q = $p.I($i, $j); $p.R[$q] = $r; $p.G[$q] = $g; $p.B[$q] = $b; $p.A[$q] = [Math]::Min(1, [Math]::Max(0, $dd / 2 - [Math]::Sqrt($dx * $dx + $dy * $dy))) } }; Put $p ([int]($cx - $dd / 2)) ([int]($cy - $dd / 2)) }

$geo = [ordered]@{}
function G($n, $x, $y, $w, $h) { $geo[$n] = @($x, $y, $w, $h) }

# ===== main decor
Layer "main"
for ($j = 0; $j -lt 220; $j++) { Rect 0 ($SCR - 220 + $j) $W 1 0 0 0 (0.40 * $j / 220) }
# minimap (square), its buttons, the micro menu panel above
$mmF = PanelFrame 380 378; Put ([Inside]::Fill($mmF, 0.3, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 1)) 0 1062
$bxs = $null; $lab = [Holes]::Label($mmF, 0.3, [ref]$bxs); $mx0 = 9999; $my0 = 9999; $mx1 = -1; $my1 = -1
for ($yy = 0; $yy -lt $mmF.H; $yy++) { for ($xx = 0; $xx -lt $mmF.W; $xx++) { $qq = $mmF.I($xx, $yy); if ($lab[$qq] -gt 0 -or $mmF.A[$qq] -ge 0.9) { if ($xx -lt $mx0) { $mx0 = $xx }; if ($xx -gt $mx1) { $mx1 = $xx }; if ($yy -lt $my0) { $my0 = $yy }; if ($yy -gt $my1) { $my1 = $yy } } } }
$mw = $mx1 - $mx0 + 1; $mh = $my1 - $my0 + 1; $mask = New-Object Img $mw, $mh
for ($yy = 0; $yy -lt $mh; $yy++) { for ($xx = 0; $xx -lt $mw; $xx++) { $q = $mask.I($xx, $yy); $mask.R[$q] = 1; $mask.G[$q] = 1; $mask.B[$q] = 1; $qq = $mmF.I($xx + $mx0, $yy + $my0); $mask.A[$q] = $(if ($lab[$qq] -gt 0 -or $mmF.A[$qq] -ge 0.9) { 1 } else { 0 }) } }
$script:mapMask = $mask.Resize(256, 256)
G "map" $mx0 (1062 + $my0) $mw $mh; G "zone" ($mx0 + 10) (1062 + $my1 - 40) ($mw - 20) 24
"map $mx0,$(1062 + $my0) $mw x $mh"
Put $HK.mbtn 388 1100; Put $HK.mbtn 388 1146; G "mail" 388 1100 39 38; G "track" 388 1146 39 38
Panel 0 990 380 72; G "micro" 9 1001 352 41
# player portrait block
# (the centre island: pet window, portrait, abilities, bags, its top at 1150 as the chat island's,
# 290 px tall; their frame lines level with the chat's)
# (the model in the opening of the frame over it: iconframe at 218 x 213, opening 18-192 = 175)
Panel 1140 1150 260 290; Rect 1180 1212 175 175 0.02 0.02 0.03 1
# (threat on the target, as retail's numerical threat: centred above the portrait block)
G "p_threat" 1210 1115 110 40
G "p_model" 1180 1212 175 175; G "p_name" 1145 1167 250 26; G "p_badge" 1158 1368 60 32
# stats
# (left of the portrait: the pet action bar window, shown with the pet: its layers below)
# abilities: xp, 3 rows (bar3 on top), health / mana
Panel 1398 1150 880 290
# (no xp bar here: the xp is the ring around the level, p_level)
$rows = [ordered]@{ bar3 = @(1190, 42, 10); bar2 = @(1240, 42, 10); bar1 = @(1290, 54, 12) }
foreach ($k in $rows.Keys) { $row = $rows[$k]; $sz = $row[1]; $gap = $row[2]; $rw = 12 * $sz + 11 * $gap; $x0 = 1833 - [int]($rw / 2)
	for ($cc = 0; $cc -lt 12; $cc++) { Slot ($x0 + $cc * ($sz + $gap)) $row[0] $sz }; G $k $x0 $row[0] $rw $sz; $geo["${k}_step"] = @(($sz + $gap), $sz) }
# (rounded troughs: the cast bar background, 2 px inside the frame; the fill 4 px inside, as the cast bar)
H3 $HK.castBg 8 8 1423 1358 820 36; H3 $HK.castBg 8 8 1423 1400 820 22
G "p_health" 1431 1361 804 30; G "p_power" 1425 1402 816 18
# bags: Blizzard's bag bar (WoW Forever) upright: the backpack on top, the 4 bags, the reagent
# bag, then the key ring's own box lying (45 x 33, as Blizzard turns it in its vertical bag bar);
# a thin column as tall as the centre panel, the same gap to it. The cells centred on the column
# and evenly spaced in the inside of its frame (its lines at 2..7 and 71..75 of the 86 px panel,
# 2..6 and 276..280 of its 290 px: inside x 2284..2346, y 1158..1425): 7 px between them, 8 above
# the first and under the last (267 px: no whole spacing gives the same everywhere)
Panel 2276 1150 86 290
$bs = 31; $bgap = 7; $bcx = 2315.5; $by = 1166
for ($i = 0; $i -lt 6; $i++) { $x = [int]($bcx - $bs / 2); $y = $by + $i * ($bs + $bgap); Slot $x $y $bs; G "bag$($i + 1)" $x $y $bs $bs }
$kh = [int][Math]::Round($bs * 33 / 45); $kx = [int]($bcx - $bs / 2); $ky = $by + 6 * ($bs + $bgap); SlotWH $kx $ky $bs $kh; G "bag7" $kx $ky $bs $kh
# opened bags: their bottom right corner at the bottom right of this box (above the ability block)
G "bagsOpen" 1663 733 579 387
G "p_cast" 1580 1086 506 30
# chat, its input box
# (bottom right: the extra bars on top, the chat under them, wider to the left; the same gap as
# between the other panels: the next panel starts where the previous one ends)
# extra bars 2 x 12
$ey = 1000 # Chat top aligned with the 290 px centre panel; extra bars stay above.
Panel 2880 $ey 560 150
for ($rr = 0; $rr -lt 2; $rr++) { for ($cc = 0; $cc -lt 12; $cc++) { Slot (2901 + $cc * 43) ($ey + 27 + $rr * 50) 36 } }
G "extra1" 2901 ($ey + 27) 509 36; G "extra2" 2901 ($ey + 77) 509 36; $geo["extra_step"] = @(43, 36); G "extraFrame" 2880 $ey 560 150
# chat, its input box
$cx0 = 2720; $cy0 = $ey + 150; $cw = 3440 - $cx0; $ch = 1440 - $cy0
Panel $cx0 $cy0 $cw $ch
H3 $HK.castBg 8 8 ($cx0 + 16) ($cy0 + $ch - 48) ($cw - 42) 28; H3 $HK.castF 14 14 ($cx0 + 14) ($cy0 + $ch - 50) ($cw - 38) 32
G "chat" $cx0 $cy0 $cw $ch; G "chatText" ($cx0 + 14) ($cy0 + 44) ($cw - 66) ($ch - 102); G "chatInput" ($cx0 + 20) ($cy0 + $ch - 48) ($cw - 50) 28; G "cog" ($cx0 + $cw - 48) ($cy0 + 10) 24 24
# reputation: Blizzard's reputation bar standing up, in its own thin panel left of the chat (as
# tall as it, the same gap to it: it ends 2 px into the chat panel, as each panel into the next);
# the trough (castBg) and the frame (castF, a piece over the fill) of the mana bar, turned a
# quarter, centred in the inside of the frame lines (x +8..+62, y +8..+274 of the 78 x 290 panel),
# 10 px from its top and bottom; the fill (p_rep, 4 px inside the frame) drawn by the game
$rw = 78; $rx = $cx0 + 2 - $rw; Panel $rx $cy0 $rw $ch
$rfx = $rx + 25; $rfy = $cy0 + 18; $rfl = 247
Put (Rot90 (H3Img $HK.castBg 8 8 ($rfl - 4) 16)) ($rfx + 2) ($rfy + 2)
G "p_rep" ($rfx + 4) ($rfy + 4) 12 ($rfl - 8); G "repFrame" $rx $cy0 $rw $ch
G "stance" 392 1008 300 40

# ===== player: over the model / the bars / the stat icons
Layer "p_over"
Put ($HK.frame.Resize(218, 213)) 1162 1194
# level: a dark disc; around it the communities gold ring (hole 69 of 95) at 60 px (1158, 1354), drawn
# by the game over p_level (72 px around it): dark, and gold with its glow as the xp fills it (Dota's
# level ring; xpring.tga, xpglow.tga)
Disc 1188 1384 46 0.03 0.03 0.04
G "p_level" 1152 1348 72 72
# (a piece of its own: the atlas is 1024 wide)
Layer "p_bars"
H3 $HK.castF 14 14 1421 1356 824 40; H3 $HK.castF 14 14 1421 1398 824 26
# reputation: the frame of its bar standing up, over the fill (left of the chat, see above)
Layer "rep_fr"; Put (Rot90 (H3Img $HK.castF 14 14 $rfl 20)) $rfx $rfy
# ===== action button frames, per bar (over the buttons)
foreach ($k in $rows.Keys) { Layer "${k}_over"; $row = $rows[$k]; $sz = $row[1]; $gap = $row[2]; $x0 = $geo[$k][0]; for ($cc = 0; $cc -lt 12; $cc++) { IconFrame ($x0 + $cc * ($sz + $gap)) $row[0] $sz } }
Layer "bags_over"; for ($i = 1; $i -le 7; $i++) { $g = $geo["bag$i"]; IconFrameWH $g[0] $g[1] $g[2] $g[3] }
Layer "extra_over"; for ($rr = 0; $rr -lt 2; $rr++) { for ($cc = 0; $cc -lt 12; $cc++) { IconFrame (2901 + $cc * 43) ($ey + 27 + $rr * 50) 36 } }
Layer "mm_mail"; Put $HK.mail 388 1104
Layer "mm_frame"; Put $mmF 0 1062
for ($j = 0; $j -lt 34; $j++) { Rect 8 (1062 + $my1 - 38 + $j) 362 1 0 0 0 (0.55 * $j / 34) }

# ===== pet: the small retail frame (ring left), its spell slots (shown with the pet)
# (the frame above the pet action bar window, its ring left of it; its bars end 6 px over the window)
$px = 822; $py = 1078
Layer "pet_frame"; Put $HK.tot $px $py
# the pet action bar: its own window left of the portrait, 2 columns x 5 rows of 42 px
Layer "pet_win"; Panel 988 1150 154 290
Layer "pet_slots"; Layer "pet_over"
for ($i = 0; $i -lt 10; $i++) { $bx = 1015 + ($i % 2) * 48; $by = 1174 + [Math]::Floor($i / 2) * 48
	Layer "pet_slots"; Slot $bx $by 42; Layer "pet_over"; IconFrame $bx $by 42; G "pet_btn$($i + 1)" $bx $by 42 42 }
# (ToT frame holes: ring 17-83 x 12-78, health 92-226 x 38-50, power 92-226 x 60-66)
G "pet" $px $py 240 98; G "pet_portrait" ($px + 16) ($py + 11) 68 68; G "pet_name" ($px + 96) ($py + 14) 130 20
G "pet_health" ($px + 92) ($py + 38) 135 13; G "pet_power" ($px + 92) ($py + 60) 135 7


# ===== target: the retail target frame (ring right); its cast above; combo sockets under the ring
$tx = 2330; $ty = 1064
Layer "t_frame"; Put $HK.tf $tx $ty
# (target frame holes: ring 261-366 x 9-115, health 10-253 x 52-84, power 10-266 x 94-106)
G "target" $tx $ty 384 134; G "t_portrait" ($tx + 259) ($ty + 8) 109 109
G "t_name" ($tx + 10) ($ty + 18) 204 24; G "t_lvl" ($tx + 214) ($ty + 18) 38 24
G "t_health" ($tx + 10) ($ty + 52) 244 33; G "t_power" ($tx + 10) ($ty + 94) 257 13
# auras (as the player drew them, at Blizzard's original size): the target's under its frame,
# between the bags and the chat, under the combo points (where its pet's frame shows); the
# player's buffs and debuffs together above the micro menu, over the minimap
G "t_auras" 2451 1225 224 189
G "p_auras" 30 615 315 335
G "t_cast" $tx 1010 250 30
Layer "sockets"
for ($i = 0; $i -lt 5; $i++) { Put ($cpt.Crop(0, 0, 12, 16).Resize(24, 32)) (2595 + $i * 18) 1186; G "combo$($i + 1)" (2601 + $i * 18) 1186 12 32 }
# target's pet (shown with it): the small retail frame mirrored, under the target frame
$qx = 2453; $qy = 1224
Layer "tpet_frame"; Put ($HK.tot.FlipH()) $qx $qy
G "tpet" $qx $qy 240 98; G "tpet_portrait" ($qx + 156) ($qy + 11) 68 68; G "tpet_name" ($qx + 14) ($qy + 14) 130 20
G "tpet_health" ($qx + 13) ($qy + 38) 135 13; G "tpet_power" ($qx + 13) ($qy + 60) 135 7
# target of target
$ox = 2600; $oy = 958
Layer "tot_frame"; Put $HK.tot $ox $oy
G "tot" $ox $oy 240 98; G "tot_portrait" ($ox + 16) ($oy + 11) 68 68; G "tot_name" ($ox + 96) ($oy + 14) 130 20; G "tot_health" ($ox + 92) ($oy + 38) 135 13

# ===== cast bars: background (under the fill) and frame (over it), for each width
function CastLayers($n, $w) { Layer "${n}_bg"; H3 $HK.castBg 8 8 2 942 ($w - 4) 26; Layer "${n}_fr"; H3 $HK.castF 14 14 0 940 $w 30 }
CastLayers "castP" 506; CastLayers "castT" 250

# ---- output
$art = "$Out\art\moba\blocks"; New-Item -ItemType Directory -Force $art | Out-Null
function Pot($n) { $p = 8; while ($p -lt $n) { $p *= 2 }; $p }
function SaveTex($img, $path) { $c = New-Object Img (Pot $img.W), (Pot $img.H); [K2]::Put($c, $img, 0, 0); $c.SaveTga($path); return @($c.W, $c.H) }
function BL($r) { "{ $($r[0]), $($SCR - $r[1] - $r[3]), $($r[2]), $($r[3]) }" }
$lua = New-Object System.Collections.ArrayList
[void]$lua.Add("-- Generated by build_moba.ps1 (moba theme, modern dress): art px, origin bottom left of the screen (3440 x $H art, 1 px = 1 screen px on 3440)")
[void]$lua.Add("local _, ns = ...")
[void]$lua.Add("ns.MOBA = { W = $W, H = $H,")
[void]$lua.Add(" back = {")
$main = $layers.main; $n = 0
for ($ty = 0; $ty -lt $H; $ty += 512) { for ($tx = 0; $tx -lt $W; $tx += 1024) {
	$tw = [Math]::Min(1024, $W - $tx); $th = [Math]::Min(512, $H - $ty); $tile = $main.Crop($tx, $ty, $tw, $th)
	$any = $false; for ($i = 0; $i -lt $tile.A.Length; $i += 7) { if ($tile.A[$i] -gt 0.01) { $any = $true; break } }; if (-not $any) { continue }
	$n++; $sz = SaveTex $tile "$art\back$n.tga"
	[void]$lua.Add("  { tex = `"back$n`", x = $tx, y = $($H - $ty - $th), w = $tw, h = $th, tw = $($sz[0]), th = $($sz[1]) },") } }
[void]$lua.Add(" },")
$pieces = @()
foreach ($k in @($layers.Keys)) { if ($k -eq "main") { continue }; $im = $layers[$k]; $b = $im.Bounds(0.01); $pc = $im.Crop($b[0], $b[1], $b[2], $b[3]); $pieces += , @($k, $pc, $b[0], $b[1]) }
foreach ($p in $pieces) { if ($p[1].W -gt 1024) { throw "piece $($p[0]) wider than the atlas: $($p[1].W)" } }
$pieces = $pieces | Sort-Object { - $_[1].H }
$AT = 1024; $px = 0; $py = 0; $rowH = 0; $place = @{}
foreach ($p in $pieces) { if ($px + $p[1].W -gt $AT) { $px = 0; $py += $rowH + 2; $rowH = 0 }; $place[$p[0]] = @($px, $py); $px += $p[1].W + 2; $rowH = [Math]::Max($rowH, $p[1].H) }
$atlas = New-Object Img $AT, (Pot ($py + $rowH)); foreach ($p in $pieces) { $q = $place[$p[0]]; [K2]::Put($atlas, $p[1], $q[0], $q[1]) }
$atlas.SaveTga("$art\front.tga"); "front atlas $($atlas.W) x $($atlas.H), $($pieces.Count) pieces"
[void]$lua.Add(" frontW = $($atlas.W), frontH = $($atlas.H),")
[void]$lua.Add(" front = {")
foreach ($p in $pieces) { $q = $place[$p[0]]; $pw = $p[1].W; $ph = $p[1].H; [void]$lua.Add("  $($p[0]) = { u = $($q[0]), v = $($q[1]), x = $($p[2]), y = $($H - $p[3] - $ph), w = $pw, h = $ph },") }
[void]$lua.Add(" },")
[void]$lua.Add(" r = {")
foreach ($k in $geo.Keys) { $g = $geo[$k]; if ($k -like "*_step") { [void]$lua.Add("  $k = { $($g[0]), $($g[1]) },") } else { [void]$lua.Add("  $k = $(BL $g),") } }
[void]$lua.Add(" },")
[void]$lua.Add("}")
[IO.File]::WriteAllText("$Out\MobaGeom.lua", ($lua -join "`n") + "`n")
# status bar fills (cast), the combo gem
# (a status bar crops its texture: the fills cover their whole canvas; the cast fill in grey, the
# cast colours of the module tint it)
foreach ($c in @(@("cast_filling-standard", "castfill"), @("cast_filling-channel", "castchan"), @("cast_interrupted", "castfail"), @("cast_uninterruptable", "castshield"))) {
	$cf = $HK[$c[0]].Clone(); for ($i = 0; $i -lt $cf.A.Length; $i++) { $cf.A[$i] = 1 }; $cf.Resize(512, 32).SaveTga("$art\$($c[1]).tga") }
$script:mapMask.SaveTga("$art\mapmask.tga")
# icon mask: the inside of the retail icon frame (its chamfered corners), over the icon box (the
# frame is drawn 1 px left of the icon, 46 / 45 of its width, as tall as it)
$bxi = $null; $labI = [Holes]::Label($HK.frame, 0.3, [ref]$bxi); $im = New-Object Img 90, 90
for ($yy = 0; $yy -lt 90; $yy++) { for ($xx = 0; $xx -lt 90; $xx++) { $q = $im.I($xx, $yy); $im.R[$q] = 1; $im.G[$q] = 1; $im.B[$q] = 1; $im.A[$q] = $(if ($labI[$HK.frame.I($xx + 2, $yy)] -ne -1) { 1 } else { 0 }) } }
$im.Resize(64, 64).SaveTga("$art\iconmask.tga")
# the level ring over p_level (72 px, 128 px textures): xpring, the gold ring where the art had it (the
# track darkened, the xp swipe as painted); xpglow, a white glow on both sides of its band (outer
# radius 30 px, hole 21.8 px; tinted warm by the game, under the xp swipe)
$ls = 128; $lk = $ls / 72
$lr = New-Object Img $ls, $ls
[K2]::Put($lr, $HK.ring.Resize([int][Math]::Round(60 * $lk), [int][Math]::Round(61 * $lk)), [int][Math]::Round(6 * $lk), [int][Math]::Round(6 * $lk))
$lr.SaveTga("$art\xpring.tga")
$gl = New-Object Img $ls, $ls; $gcx = 36 * $lk; $gcy = 36.5 * $lk; $gro = 30 * $lk; $gri = 21.8 * $lk; $gso = 3.2 * $lk; $gsi = 2.6 * $lk
for ($yy = 0; $yy -lt $ls; $yy++) { for ($xx = 0; $xx -lt $ls; $xx++) { $dx = $xx + 0.5 - $gcx; $dy = $yy + 0.5 - $gcy; $dd = [Math]::Sqrt($dx * $dx + $dy * $dy); $q = $gl.I($xx, $yy)
	$a = if ($dd -gt $gro) { [Math]::Exp(- [Math]::Pow(($dd - $gro) / $gso, 2)) } elseif ($dd -lt $gri) { [Math]::Exp(- [Math]::Pow(($gri - $dd) / $gsi, 2)) } else { 1 }
	$gl.R[$q] = 1; $gl.G[$q] = 1; $gl.B[$q] = 1; $gl.A[$q] = [float]$a } }
$gl.SaveTga("$art\xpglow.tga")
# the combo gem (COMBOPOINT, doubled pixel for pixel)
$gem = $cpt.Crop(12, 0, 6, 16); $g2 = New-Object Img 16, 32
for ($yy = 0; $yy -lt 32; $yy++) { for ($xx = 0; $xx -lt 12; $xx++) { $s = $gem.I([int][Math]::Floor($xx / 2), [int][Math]::Floor($yy / 2)); $q = $g2.I($xx, $yy); $g2.R[$q] = $gem.R[$s]; $g2.G[$q] = $gem.G[$s]; $g2.B[$q] = $gem.B[$s]; $g2.A[$q] = $gem.A[$s] } }
$g2.SaveTga("$art\gem.tga")
Get-ChildItem "$art\*.tga" | ? { $_.BaseName -notmatch '^(back\d+|front|castfill|castchan|castfail|castshield|xpring|xpglow|gem|mapmask|iconmask)$' } | % { Remove-Item -LiteralPath $_.FullName }
"done"

