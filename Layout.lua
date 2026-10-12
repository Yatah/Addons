--[[
	WC3 Console - HUD geometry and art: a Dota 2 like HUD for WoW Classic
	(compact centre block: portrait, stats, 3 action rows, health / mana,
	bags; the minimap in the corner; pet, target, target of target in their
	own panels; the chat on the right), built from Blizzard's retail HUD
	textures.

	Art from tools/hud/build_moba.ps1, geometry in MobaGeom.lua (art px,
	origin at the bottom left of the strip):
	  blocks\back*   the fixed decor (BACKGROUND strata, painted here)
	  blocks\front   pieces over something that moves (the frames over the
	                 bars, the rings...) and the panels shown with a unit
]]

local _, ns = ...
local C = ns.MOBA
local R = C.r
ns.R = R
local max, min, tonumber = math.max, math.min, tonumber

-- the rect of each module
ns.RECTS = {
	minimap = { 0, 0, 380, 378 },
	player = { 1140, 0, 260, 290 },
	bags = { 2276, 0, 86, 290 },
	micro = R.micro,
	stance = R.stance,
	bar1 = R.bar1,
	bar2 = R.bar2,
	bar3 = R.bar3,
	target = R.target,
	targettarget = R.tot,
	pet = R.pet,
	targetpet = R.tpet,
	chat = R.chat,
	extrabars = R.extraFrame,
}

-- ns.k: UI units per art px (the strip as wide as the screen minus the
-- side margins, times the HUD scale); ns.ox, ns.oy: bottom left corner of
-- the strip
function ns.ComputeScale()
	local p = ns.p
	local w = UIParent:GetWidth()
	local k = (w - 2 * (tonumber(p.marginX) or 0)) / C.W * min(1, max(0.5, tonumber(p.scale) or 1))
	ns.k = k
	ns.ox = (w - C.W * k) / 2
	ns.oy = tonumber(p.marginY) or 0
	return k
end

function ns.PlaceModule(m)
	local f, r, k = m.frame, m.rect, ns.k
	f:SetSize(max(1, r[3] * k), max(1, r[4] * k))
	ns.ClearAllPoints(f)
	ns.SetPoint(f, "BOTTOMLEFT", UIParent, "BOTTOMLEFT", ns.ox + r[1] * k, ns.oy + r[2] * k)
end

------------------------------------------------------------------------
-- Placing in a module, in art px
------------------------------------------------------------------------

-- `point` (default: bottom left) of the region at x, y; w x h when given
function ns.Place(region, m, x, y, w, h, point)
	local r, k = m.rect, ns.k
	if w then
		region:SetSize(max(0.01, w * k), max(0.01, h * k))
	end
	ns.ClearAllPoints(region)
	ns.SetPoint(region, point or "BOTTOMLEFT", m.frame, "BOTTOMLEFT", (x - r[1]) * k, (y - r[2]) * k)
end

-- over a rect { x, y, w, h }
function ns.PlaceRect(region, m, r)
	ns.Place(region, m, r[1], r[2], r[3], r[4])
end

-- a text centred on a rect, as wide as it
function ns.CenterText(fs, m, r)
	ns.Place(fs, m, r[1] + r[3] / 2, r[2] + r[4] / 2, nil, nil, "CENTER")
	fs:SetWidth(r[3] * ns.k)
	fs:SetJustifyH("CENTER")
end

-- a text over a whole bar, centred both ways
function ns.TextOnBar(fs, bar)
	ns.ClearAllPoints(fs)
	ns.SetPoint(fs, "TOPLEFT", bar, "TOPLEFT", 0, 1)
	ns.SetPoint(fs, "BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
	fs:SetJustifyH("CENTER")
	fs:SetJustifyV("MIDDLE")
	fs:SetWordWrap(false)
end

------------------------------------------------------------------------
-- Fonts: sizes in art px, they follow ns.k
------------------------------------------------------------------------

ns.fonts = setmetatable({}, { __mode = "k" })

function ns.SetFont(fs, px, flags)
	flags = flags or "OUTLINE"
	ns.fonts[fs] = { px, flags }
	fs:SetFont(ns.FONT, max(6, px * (ns.k or 1)), flags)
end

function ns.NewFont(parent, px, flags, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	ns.SetFont(fs, px, flags)
	fs:SetTextColor(1, 1, 1)
	fs:SetShadowOffset(1, -1)
	fs:SetShadowColor(0, 0, 0, 1)
	fs:SetWordWrap(false)
	return fs
end

function ns.RescaleFonts()
	local k = ns.k
	for fs, v in pairs(ns.fonts) do
		fs:SetFont(ns.FONT, max(6, v[1] * k), v[2])
	end
end

------------------------------------------------------------------------
-- Art
------------------------------------------------------------------------

function ns.Art(name)
	local themed = name == "front" or name:match("^back[1-4]$")
	if ns.p and not ns.activeArtTheme then ns.activeArtTheme = ns.p.theme == "wow_bronze" and "wow_bronze" or "original" end
	if themed and ns.activeArtTheme == "wow_bronze" then
		return ns.ART .. [[themes\wow_bronze\]] .. name
	end
	return ns.ART .. [[moba\blocks\]] .. name
end

function ns.Other(name)
	return ns.ART .. [[other\]] .. name
end

ns.BAR = ns.Other("xpProgressBar")
ns.WINDOW = { 0.05, 0.045, 0.05 } -- (inside of the windows)

-- Resolve the atlas after profile initialization, not at file-load time.

-- a piece of the front atlas on a texture
function ns.AtlasPiece(t, name)
	local p = C.front[name]
	t:SetTexture(ns.Art("front"))
	t:SetTexCoord(p.u / C.frontW, (p.u + (p.texW or p.w)) / C.frontW, p.v / C.frontH, (p.v + (p.texH or p.h)) / C.frontH)
	return p
end

-- pieces of the front atlas at their place, in a frame of the module
-- (m[field], made once) at `level`
function ns.Pieces(m, field, names, parent, level)
	local f = m[field]
	if not f then
		f = CreateFrame("Frame", nil, parent or m.frame)
		f:EnableMouse(false)
		f:SetAllPoints(m.frame)
		f.tex = {}
		for i, name in ipairs(names) do
			f.tex[i] = f:CreateTexture(nil, "ARTWORK")
			f.tex[i].piece = name
		end
		m[field] = f
	end
	f:SetFrameLevel(level or (m.frame:GetFrameLevel() + 7))
	for _, t in ipairs(f.tex) do
		local p = ns.AtlasPiece(t, t.piece)
		ns.Place(t, m, p.x, p.y, p.w, p.h)
	end
	return f
end

-- The fixed decor: the back textures over the whole strip (one frame of the
-- BACKGROUND strata), placed again after each layout
local back
ns.On("WC3C_LAYOUT", function()
	local k = ns.k
	if not back then
		back = CreateFrame("Frame", "WC3C_Art", UIParent)
		back:SetFrameStrata("BACKGROUND")
		back:SetFrameLevel(1)
		back:EnableMouse(false)
		for i, t in ipairs(C.back) do
			local tx = back:CreateTexture(nil, "BACKGROUND")
			tx:SetTexture(ns.Art(t.tex))
			tx:SetTexCoord(0, t.w / t.tw, 0, t.h / t.th)
			back[i] = tx
		end
	end
	ns.ClearAllPoints(back)
	ns.SetPoint(back, "BOTTOMLEFT", UIParent, "BOTTOMLEFT", ns.ox, ns.oy)
	back:SetSize(C.W * k, C.H * k)
	for i, t in ipairs(C.back) do
		local tx = back[i]
		ns.ClearAllPoints(tx)
		ns.SetPoint(tx, "BOTTOMLEFT", back, "BOTTOMLEFT", t.x * k, t.y * k)
		tx:SetSize(t.w * k, t.h * k)
	end
end)

-- The icon of a button cut to the inside of the retail icon frame
-- (chamfered corners: blocks\iconmask), its cooldown swipe too. (Blizzard's
-- buttons take their own mask off on each update: ours stays.)
local ICON_MASK = ns.Art("iconmask")

function ns.MaskIcon(b, icon)
	icon = icon or b.icon or b.Icon or (b:GetName() and (_G[b:GetName() .. "Icon"] or _G[b:GetName() .. "IconTexture"]))
	if b.wc3cMask or not (icon and icon.AddMaskTexture and b.CreateMaskTexture) then
		return
	end
	local mask = b:CreateMaskTexture()
	mask:SetTexture(ICON_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(icon)
	pcall(icon.AddMaskTexture, icon, mask)
	b.wc3cMask = mask
	local cd = b.cooldown or b.Cooldown
	if cd and cd.SetSwipeTexture then
		pcall(cd.SetSwipeTexture, cd, ICON_MASK)
	end
end


