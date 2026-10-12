--[[
	WC3 Console - minimap in the corner: the map fills its frame (a mask
	with chamfered corners), the zone name at its bottom; zoom with the
	mouse wheel.

	Two ways (setting "editMode", a change needs a /reload):
	  - Edit Mode (Forever): Blizzard's MinimapCluster stays alive with all
	    it holds (tracking, mail, clock, calendar and its invites, add-on
	    compartment, instance difficulty, day / night, the group finder eye
	    anchored to the map). An Edit Mode layout of the console, "WC3
	    Console" (a copy of the player's layout, only its minimap changed),
	    puts the map in the HUD's socket. The console only dresses it: its
	    mask, its frame and zone text over it, Blizzard's round frame,
	    header plate and zone text made transparent, the header buttons and
	    the day / night badge next to the map.
	    The layout is written on the player's click only, out of combat and
	    out of Edit Mode, then the interface reloads (written by an addon,
	    Blizzard's Edit Mode code would run tainted until a reload). The
	    player's own layouts are never written; /wc3c minimap restore gives
	    the previous one back.
	  - old: the map taken out of its cluster (hidden), placed again each
	    time Blizzard moves it.
]]

local _, ns = ...
local R = ns.R
local abs, floor, max, min, format = math.abs, math.floor, math.max, math.min, string.format

local function ZoneColor()
	local info = (C_PvP and C_PvP.GetZonePVPInfo) or _G.GetZonePVPInfo
	local pvpType = info and info()
	if pvpType == "sanctuary" then
		return 0.41, 0.8, 0.94
	elseif pvpType == "arena" or pvpType == "hostile" then
		return 1.0, 0.1, 0.1
	elseif pvpType == "friendly" then
		return 0.1, 1.0, 0.1
	elseif pvpType == "contested" then
		return 1.0, 0.7, 0.0
	end
	return 1.0, 0.82, 0.0
end

local PlaceZone

local function UpdateZone(m)
	m.zone.text:SetText(GetMinimapZoneText() or "")
	m.zone.text:SetTextColor(ZoneColor())
	if m.pilot then
		PlaceZone(m)
	end
end

local function UpdateMail(m)
	local v = HasNewMail() and 1 or 0.25
	m.mail.icon:SetVertexColor(v, v, v, 1)
end

-- the map drawn again at its new size
local function Redraw(mm)
	local zoom = mm:GetZoom()
	mm:SetZoom(zoom > 0 and zoom - 1 or zoom + 1)
	mm:SetZoom(zoom)
end

------------------------------------------------------------------------
-- Old way: the map out of its hidden cluster
------------------------------------------------------------------------

local placing = false
local function LayoutMap(m)
	local mm = Minimap
	local map, k = R.map, ns.k
	ns.Reparent(mm, m.frame)
	mm:SetFrameLevel(m.frame:GetFrameLevel() + 1)
	ns.SetScale(mm, 1)
	mm:SetSize(map[3] * k, map[4] * k)
	ns.Place(mm, m, map[1] + map[3] / 2, map[2] + map[4] / 2, nil, nil, "CENTER")
	Redraw(mm)
end

local function PlaceMap(m)
	if placing then return end
	if InCombatLockdown() then
		ns.RunOOC("minimap-layout", function() PlaceMap(m) end)
		return
	end
	placing = true
	ns.Try("minimap placement", LayoutMap, m)
	placing = false
end

local function LegacySetup(m)
	local mm = Minimap
	local cluster = _G.MinimapCluster
	m.tracking = (cluster and cluster.Tracking) or _G.MiniMapTracking or _G.MiniMapTrackingFrame
	if m.tracking and m.tracking.Background then
		m.tracking.Background:SetAlpha(0)
	end
	for _, name in ipairs({ "MiniMapTrackingBorder", "MiniMapTrackingButtonBorder", "MiniMapTrackingBackground" }) do
		if _G[name] then
			_G[name]:SetAlpha(0)
		end
	end
	ns.Reparent(mm, m.frame)
	if cluster then
		ns.Reparent(cluster, ns.hider)
		if cluster.SetHeaderUnderneath then
			hooksecurefunc(cluster, "SetHeaderUnderneath", function()
				ns.Defer("minimap-layout", function()
					PlaceMap(m)
				end, true)
			end)
		end
	end
	for _, name in ipairs({ "MinimapBorder", "MinimapBorderTop", "MinimapBackdrop", "MinimapCompassTexture", "MinimapNorthTag",
		"MinimapZoomIn", "MinimapZoomOut", "MiniMapWorldMapButton", "MinimapToggleButton", "MinimapZoneTextButton",
		"MiniMapMailFrame", "GameTimeFrame", "TimeManagerClockButton" }) do
		ns.Reparent(_G[name], ns.hider)
	end
	ns.Reparent(mm.ZoomIn, ns.hider)
	ns.Reparent(mm.ZoomOut, ns.hider)
	-- the map under its frame, cut to its chamfered inside
	mm:SetMaskTexture(ns.Art("mapmask"))
	if mm.SetArchBlobRingScalar then
		mm:SetArchBlobRingScalar(0)
	end
	if mm.SetQuestBlobRingScalar then
		mm:SetQuestBlobRingScalar(0)
	end
	_G.GetMinimapShape = function()
		return "SQUARE"
	end
	mm:EnableMouseWheel(true)
	mm:SetScript("OnMouseWheel", function(self, delta)
		local zoom = self:GetZoom()
		if delta > 0 then
			if zoom < self:GetZoomLevels() - 1 then
				self:SetZoom(zoom + 1)
			end
		elseif zoom > 0 then
			self:SetZoom(zoom - 1)
		end
	end)
	ns.HookPosition(mm, function()
		PlaceMap(m)
	end, function() return placing end)
end

local function LegacyLayout(m)
	local k = ns.k
	PlaceMap(m)
	ns.Pieces(m, "front", { "mm_frame" }, m.frame, m.frame:GetFrameLevel() + 4)
	ns.PlaceRect(m.zone, m, R.zone)
	local mail = ns.MOBA.front.mm_mail
	ns.Place(m.mail, m, mail.x, mail.y, mail.w, mail.h)
	-- (the tracking button leaves the hidden cluster)
	local t, tr = m.tracking, R.track
	if t then
		ns.Reparent(t, m.frame)
		t:SetFrameLevel(m.frame:GetFrameLevel() + 5)
		local h = t:GetHeight()
		if h and h > 0 then
			ns.SetScale(t, 26 * k / h)
		end
		ns.Follow(m, t, "CENTER", tr[1] + tr[3] / 2, tr[2] + tr[4] / 2)
	end
end

------------------------------------------------------------------------
-- Edit Mode: Blizzard's minimap placed by a layout, dressed by the console
------------------------------------------------------------------------

local LAYOUT = "WC3 Console"
-- Blizzard's own mask (Blizzard_Minimap\Camelot\Skin.lua, both modes), given back
local BLIZZARD_MASK = "ui-hud-minimap-frame-generic-mask"
local TOLERANCE = 12 -- UI units: the farthest the console moves the map by itself (Edit Mode's rounding)
local HEADER_GAP = 12 -- art px between the map and Blizzard's header buttons, on its right
local HEADER_W = 56 -- UI units: Blizzard's header plate (transparent), narrowed to its clock
local HEADER_LEFT = 21 -- UI units: the mail / tracking icons hang on the left of the plate
local DIEL_INSET = 14 -- art px: the day / night badge in the top right corner of the map

local P = { asked = false } -- state of the Edit Mode way

function ns.MinimapPilotAvailable()
	local c = _G.MinimapCluster
	return (C_EditMode and C_EditMode.GetLayouts and C_EditMode.SaveLayouts and Enum and Enum.EditModeSystem
		and Enum.EditModeMinimapSetting and Enum.EditModeLayoutType and _G.EditModePresetLayoutManager and _G.EditModeManagerFrame
		and c and type(c.MinimapContainer) == "table" and type(c.BorderTop) == "table" and _G.Minimap) and true or false
end

local function EditModeReady()
	local em = _G.EditModeManagerFrame
	return em and em.IsInitialized and em:IsInitialized() and true or false
end

local function InEditMode()
	local em = _G.EditModeManagerFrame
	return em and em.IsEditModeActive and em:IsEditModeActive() and true or false
end

-- every layout numbered as Blizzard does: its presets first, then the saved
-- ones (C_EditMode.GetLayouts gives the saved ones and the active index)
local function Layouts()
	local info = C_EditMode.GetLayouts()
	if type(info) ~= "table" or type(info.layouts) ~= "table" then
		return nil
	end
	local all = _G.EditModePresetLayoutManager:GetCopyOfPresetLayouts()
	local presets = #all
	for _, l in ipairs(info.layouts) do
		all[#all + 1] = l
	end
	return all, info.activeLayout, presets
end

local function FindLayout(all, name, kind)
	for i, l in ipairs(all) do
		if l.layoutName == name and (kind == nil or l.layoutType == kind) then
			return i
		end
	end
end

local function FindOurs(all)
	for i, l in ipairs(all) do
		if l.layoutName == LAYOUT and l.layoutType ~= Enum.EditModeLayoutType.Preset then
			return i
		end
	end
end

local function MinimapSystem(l)
	for _, s in ipairs(l and l.systems or {}) do
		if s.system == Enum.EditModeSystem.Minimap then
			return s
		end
	end
end

local function GetSetting(sys, setting)
	for _, s in ipairs(sys and sys.settings or {}) do
		if s.setting == setting then
			return s.value
		end
	end
end

local function SetSetting(sys, setting, value)
	for _, s in ipairs(sys.settings) do
		if s.setting == setting then
			s.value = value
			return
		end
	end
	table.insert(sys.settings, { setting = setting, value = value })
end

local function Copy(t)
	if type(t) ~= "table" then
		return t
	end
	local c = {}
	for k, v in pairs(t) do
		c[k] = Copy(v)
	end
	return c
end

-- Where the layout must put the cluster for the map to fill the socket
-- (UI units from the bottom left of the screen). Edit Mode sizes the map by
-- steps of 10 % (50 to 200 %, saved as 0 to 15): the nearest one, the rest
-- made by the map's own size. The cluster is anchored by its top: the map's
-- container hangs from it (Blizzard's XML: 10, -30), the map in its centre;
-- the cluster's size (its header) never moves the map then.
local function Target()
	local c = MinimapCluster
	local map, k = R.map, ns.k
	local cx, cy = ns.ox + (map[1] + map[3] / 2) * k, ns.oy + (map[2] + map[4] / 2) * k
	local pct = floor(map[3] * k / (P.baseW or 198) * 10 + 0.5) * 10
	pct = max(50, min(200, pct))
	local s, cs = pct / 100, c:GetScale() or 1
	local container = c.MinimapContainer
	local p = container.defaultFramePoints and container.defaultFramePoints[1]
	local dx, dy = p and p.offsetX or 10, p and p.offsetY or -30
	local h = container:GetHeight() or 0
	return {
		size = (pct - 50) / 10,
		pct = pct,
		x = cx - dx * cs,
		y = cy - (dy - h * s / 2) * cs,
		cx = cx,
		cy = cy,
		w = map[3] * k,
		h = map[4] * k,
	}
end

local function Signature(t)
	return format("%d:%.1f:%.1f", t.size, t.x, t.y)
end

local function SetMinimap(l, t)
	local S = Enum.EditModeMinimapSetting
	local sys = MinimapSystem(l)
	if not sys then
		sys = { system = Enum.EditModeSystem.Minimap, settings = {} }
		l.systems = l.systems or {}
		table.insert(l.systems, sys)
	end
	sys.anchorInfo = { point = "TOP", relativeTo = "UIParent", relativePoint = "BOTTOMLEFT", offsetX = t.x, offsetY = t.y }
	sys.anchorInfo2 = nil
	sys.isInDefaultPosition = false
	SetSetting(sys, S.HeaderUnderneath, 0)
	SetSetting(sys, S.Size, t.size)
	-- (rotation and icon size: the player's)
	if GetSetting(sys, S.RotateMinimap) == nil then
		SetSetting(sys, S.RotateMinimap, 0)
	end
	if GetSetting(sys, S.IconScale) == nil then
		SetSetting(sys, S.IconScale, 5)
	end
end

------------------------------------------------------------------------
-- The dress: over Blizzard's map, following it wherever Edit Mode puts it
------------------------------------------------------------------------

function PlaceZone(m)
	local z, r, k = m.zone, R.zone, ns.k
	-- (as wide as its text: the zoom buttons and the eye stay clickable)
	local w = min(r[3], (z.text:GetStringWidth() or 0) / k + 16)
	ns.Place(z, P.sm, r[1] + r[3] / 2, r[2] + r[4] / 2, w, r[4], "CENTER")
end

-- Blizzard's header buttons (all hung on its header plate) on the right of
-- the map, by their top: the plate is the only one moved. (Blizzard anchors
-- it again when the header setting is applied: placed again right after.)
local function PlaceHeader()
	if not P.skinned then
		return
	end
	local bt = MinimapCluster.BorderTop
	ns.ClearAllPoints(bt)
	ns.SetPoint(bt, "TOPLEFT", Minimap, "TOPRIGHT", HEADER_GAP * ns.k + HEADER_LEFT, 0)
	bt:SetWidth(HEADER_W)
end

-- the day / night badge (Forever) in the top right corner of the map
-- (Blizzard anchors it again when the map's size is applied)
local function PlaceDiel()
	local d = MinimapCluster.DielFrame
	if not (P.skinned and d) then
		return
	end
	local s = d:GetScale() or 1
	local w, h = d:GetSize()
	local inset = DIEL_INSET * ns.k
	ns.ClearAllPoints(d)
	ns.SetPoint(d, "CENTER", Minimap, "TOPRIGHT", -inset / s - (w or 0) / 2, -inset / s - (h or 0) / 2)
end

-- Is the map where the layout puts it in the socket: Edit Mode's size step
-- of the socket, its centre less than TOLERANCE from the socket's (Edit
-- Mode's rounding)? nil: not known yet. Also gives the nudge that puts it
-- exactly there (its units) and its scale in UI units.
local function Fits()
	local mm, t = Minimap, P.target
	local ms = mm:GetEffectiveScale() / UIParent:GetEffectiveScale()
	local cx, cy = mm:GetCenter()
	if not (t and cx and cy and ms and ms > 0) then
		return nil
	end
	local ox = (P.offX or 0) * ms + (t.cx - cx * ms)
	local oy = (P.offY or 0) * ms + (t.cy - cy * ms)
	local step = abs((MinimapCluster.MinimapContainer:GetScale() or 1) - t.pct / 100) < 0.005
	return step and abs(ox) <= TOLERANCE and abs(oy) <= TOLERANCE, ox / ms, oy / ms, ms
end

local RemoveSkin

-- the map at the socket's size, nudged on its centre; moved or resized in
-- Edit Mode: Blizzard's minimap as Blizzard made it
local function FitMap()
	if not P.skinned then
		return
	end
	local fits, offX, offY, ms = Fits()
	if fits == nil then
		return
	end
	if not fits then
		P.far = true
		RemoveSkin()
		return
	end
	P.far = false
	local mm, t = Minimap, P.target
	local w, h = t.w / ms, t.h / ms
	if abs(mm:GetWidth() - w) > 0.01 or abs(mm:GetHeight() - h) > 0.01 then
		mm:SetSize(w, h)
		Redraw(mm)
	end
	if abs(offX - (P.offX or 0)) > 0.001 or abs(offY - (P.offY or 0)) > 0.001 or not P.anchored then
		P.offX, P.offY, P.anchored = offX, offY, true
		ns.ClearAllPoints(mm)
		ns.SetPoint(mm, "CENTER", MinimapCluster.MinimapContainer, "CENTER", P.offX, P.offY)
	end
end

-- Blizzard's textures doing the job of the console's frame and zone text:
-- transparent (Blizzard shows and hides them: never hidden). The cluster is
-- wider than the corner of the screen it sits in: not pushed back on the
-- screen, its empty area lets the mouse through. Off: Blizzard's values
-- (their XML) given back.
local function Dress(on)
	local c = MinimapCluster
	for _, t in ipairs({ _G.MinimapCompassTexture, _G.MinimapCompassTextureUnderlay, c.BorderTop, c.ZoneTextButton }) do
		if type(t) == "table" and t.SetAlpha then
			t:SetAlpha(on and 0 or 1)
		end
	end
	if type(c.ZoneTextButton) == "table" then
		c.ZoneTextButton:EnableMouse(not on)
	end
	c:SetClampedToScreen(not on)
	c:EnableMouse(not on)
end

local function PlaceSkin(m)
	local skin, k, r, map = P.skin, ns.k, m.rect, R.map
	skin:SetScale(UIParent:GetEffectiveScale())
	skin:SetSize(r[3] * k, r[4] * k)
	ns.ClearAllPoints(skin)
	ns.SetPoint(skin, "CENTER", Minimap, "CENTER", (r[1] + r[3] / 2 - map[1] - map[3] / 2) * k, (r[2] + r[4] / 2 - map[2] - map[4] / 2) * k)
	skin:SetFrameLevel(Minimap:GetFrameLevel() + 1)
	ns.Pieces(P.sm, "front", { "mm_frame" }, skin, skin:GetFrameLevel() + 3)
	m.zone:SetFrameLevel(skin:GetFrameLevel() + 6)
	PlaceZone(m)
end

local function ApplySkin(m)
	local mm = Minimap
	if not P.skinned then
		P.skinned = true
		Dress(true)
		mm:SetMaskTexture(ns.Art("mapmask"))
	end
	FitMap()
	PlaceSkin(m)
	PlaceHeader()
	PlaceDiel()
	P.skin:Show()
end

local function HeaderUnderneath()
	local c = MinimapCluster
	if c.GetSettingValueBool then
		local ok, v = pcall(c.GetSettingValueBool, c, Enum.EditModeMinimapSetting.HeaderUnderneath)
		return ok and v
	end
end

function RemoveSkin()
	if not P.skinned then
		return
	end
	P.skinned = false
	P.skin:Hide()
	local c, mm = MinimapCluster, Minimap
	Dress(false)
	mm:SetMaskTexture(BLIZZARD_MASK)
	mm:SetSize(P.baseW, P.baseH)
	ns.ClearAllPoints(mm)
	ns.SetPoint(mm, "CENTER", c.MinimapContainer, "CENTER", 0, 0)
	P.offX, P.offY, P.anchored = 0, 0, false
	Redraw(mm)
	-- Blizzard's header and badge where Blizzard puts them (Minimap.lua,
	-- Camelot\Diel.lua)
	local bt = c.BorderTop
	ns.ClearAllPoints(bt)
	if HeaderUnderneath() then
		ns.SetPoint(bt, "BOTTOM", c, "BOTTOM", 15, 2)
	elseif bt.defaultFramePoints and #bt.defaultFramePoints > 0 then
		for _, p in ipairs(bt.defaultFramePoints) do
			ns.SetPoint(bt, p.point, p.relativeTo, p.relativePoint, p.offsetX, p.offsetY)
		end
	else
		ns.SetPoint(bt, "TOP", c, "TOP", 15, -4)
	end
	bt:SetWidth(P.btW)
	local d = c.DielFrame
	if d then
		local s = min(1, c.MinimapContainer:GetScale() or 1)
		ns.ClearAllPoints(d)
		ns.SetPoint(d, "CENTER", 63 * s, 72 * s)
	end
end

------------------------------------------------------------------------
-- Writing the layout (the player's click only)
------------------------------------------------------------------------

local function CanWrite()
	if InCombatLockdown() then
		ns.Print("the minimap's Edit Mode layout is written out of combat only.")
		return false
	end
	if not EditModeReady() then
		ns.Print("Edit Mode is not ready yet, try again in a moment.")
		return false
	end
	if InEditMode() then
		ns.Print("close Edit Mode first (its unsaved changes would be lost).")
		return false
	end
	return true
end

local function LayoutLabel(l)
	return l and l.layoutName or "?"
end

-- "WC3 Console" made (a copy of the active layout) or brought up to date,
-- made active, then the reload
function P.Apply(m)
	if not CanWrite() then
		return
	end
	local all, active, presets = Layouts()
	if not all then
		ns.Print("Edit Mode gives no layout.")
		return
	end
	local T = Enum.EditModeLayoutType
	local t = Target()
	local ours = FindOurs(all)
	local current = all[active]
	m.db.editMode = true
	if not ours then
		if C_EditMode.IsValidLayoutName and not C_EditMode.IsValidLayoutName(LAYOUT) then
			ns.Print("Edit Mode refuses the layout name \"" .. LAYOUT .. "\".")
			return
		end
		local limit = Constants and Constants.EditModeConsts and Constants.EditModeConsts.EditModeMaxLayoutsPerType or 5
		local count, highest = {}, {}
		for i, l in ipairs(all) do
			count[l.layoutType] = (count[l.layoutType] or 0) + 1
			highest[l.layoutType] = i
		end
		local kind = T.Account
		if (count[kind] or 0) >= limit then
			kind = T.Character
			if (count[kind] or 0) >= limit then
				ns.Print("Edit Mode already has " .. limit .. " account and " .. limit .. " character layouts: delete one first.")
				return
			end
		end
		local copy = Copy(current or all[1])
		copy.layoutName, copy.layoutType = LAYOUT, kind
		SetMinimap(copy, t)
		-- (where Blizzard puts a new layout of that kind: EditModeManager MakeNewLayout)
		local index = highest[kind] and highest[kind] + 1 or (kind == T.Character and highest[T.Account] and highest[T.Account] + 1) or presets + 1
		table.insert(all, index, copy)
		ns.cdb.minimapLayout = current and { name = current.layoutName, kind = current.layoutType } or nil
		ns.cdb.minimapApplied = Signature(t)
		C_EditMode.SaveLayouts({ layouts = all, activeLayout = index })
		if C_EditMode.OnLayoutAdded then
			C_EditMode.OnLayoutAdded(index, true, false)
		else
			C_EditMode.SetActiveLayout(index)
		end
	else
		SetMinimap(all[ours], t)
		if ours ~= active then
			ns.cdb.minimapLayout = current and { name = current.layoutName, kind = current.layoutType } or nil
		end
		ns.cdb.minimapApplied = Signature(t)
		C_EditMode.SaveLayouts({ layouts = all, activeLayout = ours })
		if ours ~= active then
			C_EditMode.SetActiveLayout(ours)
		end
	end
	ReloadUI()
end

-- back to the layout active before "WC3 Console" (or Blizzard's default),
-- and to the old minimap; "WC3 Console" stays in the list
function P.Restore(m)
	if not CanWrite() then
		return
	end
	local all, active = Layouts()
	if not all then
		return
	end
	local prev = ns.cdb.minimapLayout
	local index = prev and FindLayout(all, prev.name, prev.kind)
	if not index then
		local default = C_EditMode.GetEditModeDefaultLayout and C_EditMode.GetEditModeDefaultLayout()
		for i, l in ipairs(all) do
			if l.layoutType == Enum.EditModeLayoutType.Preset and l.layoutIndex == default then
				index = i
				break
			end
		end
	end
	index = index or 1
	m.db.editMode = false
	ns.cdb.minimapLayout, ns.cdb.minimapApplied = nil, nil
	if index ~= active then
		C_EditMode.SetActiveLayout(index)
	end
	ReloadUI()
end

local function Legacy(m)
	m.db.editMode = false
	ReloadUI()
end

local TEXTS = {
	create = "Put Blizzard's minimap in the HUD through Edit Mode?\n\nWC3 Console adds the layout \"" .. LAYOUT .. "\": a copy of your layout \"%s\" where only the minimap moves. Your own layouts are not changed. The interface then reloads.\n\nBack to \"%s\" at any time: /wc3c minimap restore",
	activate = "Your Edit Mode layout is \"%s\", not \"" .. LAYOUT .. "\": the minimap stays where that layout puts it.\n\nActivate \"" .. LAYOUT .. "\" (the minimap in the HUD)? The interface then reloads.\n\nBack to \"%s\" at any time: /wc3c minimap restore",
	update = "The minimap is no longer in its place in the HUD (HUD size, screen or Edit Mode changed).\n\nSave its place again in the layout \"" .. LAYOUT .. "\"? Only the minimap of that layout changes. The interface then reloads.",
}

local function Ask(m, kind, current)
	P.asked = true
	local W = ns.W
	if not (W and W.Panel) then
		ns.Print("minimap: /wc3c minimap apply puts Blizzard's minimap in the HUD (Edit Mode layout \"" .. LAYOUT .. "\", reload).")
		return
	end
	local f = P.dialog
	if not f then
		f = W.Panel("WC3C_MinimapDialog", UIParent, 440, 190)
		f:SetPoint("CENTER", UIParent, "CENTER", 0, 140)
		f.title:SetText("WC3 Console - minimap")
		f.text = W.Label(f, "", 12)
		f.text:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -32)
		f.text:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -32)
		f.text:SetJustifyH("LEFT")
		f.text:SetJustifyV("TOP")
		f.text:SetWordWrap(true)
		f.apply = W.Button(f, "Apply and reload", 150, function()
			f:Hide()
			P.Apply(m)
		end)
		f.apply:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 12)
		f.later = W.Button(f, "Not now", 110, function()
			f:Hide()
		end)
		f.later:SetPoint("BOTTOM", f, "BOTTOM", 10, 12)
		f.old = W.Button(f, "Old minimap", 120, function()
			f:Hide()
			Legacy(m)
		end)
		f.old:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 12)
		tinsert(UISpecialFrames, "WC3C_MinimapDialog")
		P.dialog = f
	end
	local name = LayoutLabel(current)
	f.kind = kind
	f.text:SetText(format(TEXTS[kind], name, name))
	f:Show()
end

-- Each layout: dressed while "WC3 Console" is the active layout, Blizzard's
-- minimap as Blizzard made it otherwise; the dialog once per session
local function Sync(m)
	if not EditModeReady() then
		return -- (Core lays out again on EDIT_MODE_LAYOUTS_UPDATED)
	end
	local all, active = Layouts()
	if not all then
		return
	end
	P.target = Target()
	local ours = FindOurs(all)
	local quiet = P.asked or InCombatLockdown() or InEditMode()
	if ours and ours == active then
		local fits = Fits()
		P.far = fits == false
		if P.far then
			RemoveSkin()
		else
			ApplySkin(m)
			if fits == nil then
				C_Timer.After(0.2, FitMap) -- (the map's place not computed yet)
			end
		end
		local sys = MinimapSystem(all[ours])
		local stale = P.far or GetSetting(sys, Enum.EditModeMinimapSetting.Size) ~= P.target.size
			or GetSetting(sys, Enum.EditModeMinimapSetting.HeaderUnderneath) ~= 0
		if stale and not quiet then
			if ns.cdb.minimapApplied == Signature(P.target) then
				-- (saved for this very place already: no loop of reloads)
				P.asked = true
				ns.Print("minimap: Edit Mode did not put the map where it was saved, details: /wc3c minimap status")
			else
				Ask(m, "update", all[active])
			end
		end
	else
		P.far = false
		RemoveSkin()
		if not quiet then
			Ask(m, ours and "activate" or "create", all[active])
		end
	end
end

local function PilotSetup(m)
	local mm, c = Minimap, MinimapCluster
	P.baseW = (mm:GetWidth() or 0) > 0 and mm:GetWidth() or 198
	P.baseH = (mm:GetHeight() or 0) > 0 and mm:GetHeight() or 198
	P.btW = (c.BorderTop:GetWidth() or 0) > 0 and c.BorderTop:GetWidth() or 175
	local skin = CreateFrame("Frame", "WC3C_MinimapSkin", mm)
	-- (the size of the console's art whatever Edit Mode's size of the map)
	if skin.SetIgnoreParentScale then
		skin:SetIgnoreParentScale(true)
	end
	skin:EnableMouse(false)
	skin:Hide()
	P.skin = skin
	P.sm = { frame = skin, rect = m.rect } -- (ns.Place / ns.Pieces over the skin)
	-- Blizzard anchors these again in its own code (Edit Mode's header and
	-- size settings, the rotation's mask): placed again right after, only
	-- while dressed
	if c.SetHeaderUnderneath then
		hooksecurefunc(c, "SetHeaderUnderneath", function()
			PlaceHeader()
			C_Timer.After(0, FitMap)
		end)
	end
	if c.SetEditModeScale then
		hooksecurefunc(c, "SetEditModeScale", function()
			PlaceDiel()
			C_Timer.After(0, FitMap)
		end)
	end
	hooksecurefunc(mm, "SetMaskTexture", function(self)
		if P.skinned and not P.masking then
			P.masking = true
			self:SetMaskTexture(ns.Art("mapmask"))
			P.masking = false
		end
	end)
	_G.GetMinimapShape = function()
		return P.skinned and "SQUARE" or "ROUND"
	end
end

------------------------------------------------------------------------
-- /wc3c minimap [apply | restore | old | status]
------------------------------------------------------------------------

function ns.MinimapCommand(rest)
	local m = ns.moduleByKey.minimap
	local cmd = (rest or ""):lower()
	if not (m and m.frame) then
		ns.Print("the minimap module is off.")
		return
	end
	local available = ns.MinimapPilotAvailable()
	if cmd == "apply" then
		if not available then
			ns.Print("this client has no Edit Mode minimap: the old minimap only.")
		elseif not m.pilot then
			m.db.editMode = true
			ns.Print("minimap through Edit Mode after /reload (the layout is offered then).")
		else
			P.Apply(m)
		end
	elseif cmd == "restore" then
		if available then
			P.Restore(m)
		end
	elseif cmd == "old" then
		Legacy(m)
	else
		ns.Print("minimap: " .. (m.pilot and "through Edit Mode" or "old way") .. (m.db.editMode ~= m.pilot and available and " (changes after /reload)" or ""))
		if available and EditModeReady() then
			local all, active = Layouts()
			local ours = all and FindOurs(all)
			ns.Print("  active layout: \"" .. LayoutLabel(all and all[active]) .. "\", \"" .. LAYOUT .. "\": " .. (ours and (ours == active and "active" or "not active") or "none"))
			local t = Target()
			ns.Print(format("  HUD socket: size step %d%%, cluster top at %.1f, %.1f", t.pct, t.x, t.y))
			local sys = ours and MinimapSystem(all[ours])
			local a = sys and sys.anchorInfo
			if a then
				ns.Print(format("  saved: %s %s %s %.1f, %.1f, size step %d%%", tostring(a.point), tostring(a.relativeTo), tostring(a.relativePoint),
					a.offsetX or 0, a.offsetY or 0, (GetSetting(sys, Enum.EditModeMinimapSetting.Size) or 0) * 10 + 50))
			end
			if P.skinned then
				ns.Print(format("  map moved by the console: %.1f, %.1f%s", P.offX or 0, P.offY or 0, P.far and " (too far: left to Edit Mode)" or ""))
			end
			local prev = ns.cdb.minimapLayout
			if prev then
				ns.Print("  /wc3c minimap restore: back to \"" .. tostring(prev.name) .. "\"")
			end
		end
		ns.Print("/wc3c minimap apply | restore | old | status")
	end
end

------------------------------------------------------------------------
-- The module
------------------------------------------------------------------------

ns.RegisterModule({
	key = "minimap",
	label = "Minimap",
	order = 10,
	level = 10,
	defaults = { zoneText = true, editMode = false, hudPlacementVersion = 0 },
	settings = {
		{ type = "toggle", key = "zoneText", label = "Zone text" },
		{ type = "toggle", key = "editMode", label = "Blizzard's minimap via Edit Mode (reload)" },
	},
	Create = function(m)
		-- Restore the original HUD placement once for existing profiles too.
		-- Later, an explicit Edit Mode opt-in remains saved across reloads.
		if (tonumber(m.db.hudPlacementVersion) or 0) < 1 then
			m.db.editMode = false
			m.db.hudPlacementVersion = 1
		end
		m.pilot = m.db.editMode and ns.MinimapPilotAvailable()
		if m.pilot then
			PilotSetup(m)
		end
		local f = m.pilot and P.skin or m.frame
		local base = m.pilot and P.skin:GetFrameLevel() or f:GetFrameLevel()
		-- zone text (click: world map)
		m.zone = CreateFrame("Button", "WC3C_ZoneText", f)
		m.zone:SetFrameLevel(base + 6)
		m.zone.text = ns.NewFont(m.zone, 15)
		ns.SetPoint(m.zone.text, "CENTER")
		m.zone:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:AddLine(GetRealZoneText() or "", 1, 1, 1)
			local sub = GetSubZoneText() or ""
			if sub ~= "" then
				GameTooltip:AddLine(sub, ZoneColor())
			end
			GameTooltip:Show()
		end)
		m.zone:SetScript("OnLeave", GameTooltip_Hide)
		m.zone:SetScript("OnClick", function()
			ToggleWorldMap()
		end)
		-- mail (lit when there is new mail; Edit Mode: Blizzard's own icon,
		-- in its header)
		m.mail = CreateFrame("Frame", "WC3C_Mail", m.frame)
		m.mail:SetFrameLevel(m.frame:GetFrameLevel() + 5)
		m.mail.icon = m.mail:CreateTexture(nil, "ARTWORK")
		m.mail.icon:SetAllPoints()
		ns.AtlasPiece(m.mail.icon, "mm_mail")
		m.mail:EnableMouse(true)
		m.mail:SetScript("OnEnter", function(self)
			if not HasNewMail() then
				return
			end
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
			local senders = { GetLatestThreeSenders() }
			GameTooltip:AddLine(#senders > 0 and (HAVE_MAIL_FROM or "Unread mail from:") or (HAVE_MAIL or "You have unread mail"), 1, 1, 1)
			for _, s in ipairs(senders) do
				GameTooltip:AddLine(s)
			end
			GameTooltip:Show()
		end)
		m.mail:SetScript("OnLeave", GameTooltip_Hide)
		if m.pilot then
			m.mail:Hide()
		else
			LegacySetup(m)
		end
		local function Zone()
			UpdateZone(m)
		end
		local function Mail()
			UpdateMail(m)
		end
		for _, e in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
			ns.On(e, Zone)
		end
		for _, e in ipairs({ "UPDATE_PENDING_MAIL", "MAIL_INBOX_UPDATE", "MAIL_CLOSED", "PLAYER_ENTERING_WORLD" }) do
			ns.On(e, Mail)
		end
	end,
	Layout = function(m)
		if m.pilot then
			Sync(m)
		else
			LegacyLayout(m)
		end
		m.zone:SetShown(m.db.zoneText)
		UpdateZone(m)
		UpdateMail(m)
		if (m.db.editMode and ns.MinimapPilotAvailable()) ~= m.pilot and not P.switchNotice then
			P.switchNotice = true
			ns.Print("the minimap changes way after /reload.")
		end
	end,
})

-- (for the tests: the Edit Mode way's state)
ns.MinimapPilot = P
