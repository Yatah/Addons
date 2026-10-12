--[[
	WC3 Console - pet panels, each shown with its unit (unit watch)
	  pet        your pet: round portrait, health / power, cast bar over the
	             name, above its action bar (its own window, 2 x 5, left of
	             the player portrait)
	  targetpet  the pet of your target (mirrored, under the target panel);
	             no events for this unit: refreshed 5 times a second
]]

local _, ns = ...
local R = ns.R

local SLOTS = _G.NUM_PET_ACTION_SLOTS or 10

local PANELS = {
	pet = { frame = "pet_frame", portrait = "pet_portrait", name = "pet_name", health = "pet_health", power = "pet_power" },
	targetpet = { frame = "tpet_frame", portrait = "tpet_portrait", name = "tpet_name", health = "tpet_health", power = "tpet_power" },
}

local function Update(m)
	if UnitExists(m.unit) then
		ns.UpdateUnitHealth(m)
		ns.UpdateUnitPower(m)
	end
end

-- name and level, values, cast
local function UpdateInfo(m)
	local unit = m.unit
	if not UnitExists(unit) then
		return
	end
	local name, level = ns.UnitDisplayName(unit), UnitLevel(unit)
	if ns.Num(level) and level > 0 and not ns.IsSecret(name) then
		pcall(m.name.SetFormattedText, m.name, "%s |cffc8c8c8%d|r", name, level)
	else
		pcall(m.name.SetText, m.name, name)
	end
	Update(m)
	ns.CastBarRefresh(m.cast)
end

local function CreatePanel(m, unit)
	local f = m.frame
	local base = f:GetFrameLevel()
	m.unit = unit
	f:SetAttribute("unit", unit)
	m.portrait = ns.NewPortrait(f, unit)
	m.portrait:SetFrameLevel(base + 2)
	m.health = ns.NewBar(f, base + 5, "PLAYER_HEALTH")
	m.power = ns.NewBar(f, base + 5, "MANA")
	m.button = ns.UnitButton("WC3C_" .. m.key .. "UnitButton", f, unit, base + 12)
	local texts = CreateFrame("Frame", nil, f)
	texts:SetFrameLevel(base + 9)
	texts:SetAllPoints(f)
	m.name = ns.NewFont(texts, 13)
	m.name:SetTextColor(1, 0.82, 0)
	m.healthText = ns.NewFont(texts, 10)
	m.cast = ns.NewCastBar(m, unit, base + 8)
	-- shown with its unit
	RegisterUnitWatch(f)
	f:HookScript("OnShow", function()
		UpdateInfo(m)
	end)
end

local function LayoutPanel(m)
	local P = PANELS[m.key]
	ns.PlaceRect(m.portrait, m, R[P.portrait])
	ns.Pieces(m, "front", { P.frame }, m.frame, m.frame:GetFrameLevel() + 3)
	ns.PlaceRect(m.health, m, R[P.health])
	ns.PlaceRect(m.power, m, R[P.power])
	ns.PlaceRect(m.button, m, m.rect)
	ns.TextOnBar(m.healthText, m.health)
	-- the cast over the name
	local cr = R[P.name]
	ns.LayoutCastBar(m.cast, m, (m.key == "targetpet" and R.tpet_cast) or { cr[1], cr[2] + cr[4] + 3, cr[3], cr[4] })
	ns.CenterText(m.name, m, R[P.name])
	UpdateInfo(m)
end

------------------------------------------------------------------------
-- Your pet: Blizzard's pet action buttons in the window of the panel
------------------------------------------------------------------------

local function PetButtons()
	local list = {}
	local bar = _G.PetActionBar
	for i = 1, SLOTS do
		list[i] = (bar and bar.actionButtons and bar.actionButtons[i]) or _G["PetActionButton" .. i]
	end
	return list
end

local placing = false
local function PlaceSpells(m)
	if placing or not m.db.spells then
		return
	end
	if InCombatLockdown() then
		ns.RunOOC("petspells", function()
			PlaceSpells(m)
		end)
		return
	end
	placing = true
	ns.Try("pet action placement", function()
		local k, level = ns.k, m.frame:GetFrameLevel() + 4
		for i, b in ipairs(m.spells) do
			local g = R["pet_btn" .. i]
			if g then
				if not b.wc3cNative then
					local w = b:GetWidth()
					b.wc3cNative = (w and w > 0) and w or 30
					b.wc3cZoom = 0.08
					-- (Blizzard lays its bar out again: put back on the next frame)
					hooksecurefunc(b, "SetPoint", function()
						if not placing then
							ns.Defer("pet-spells-layout", function()
								PlaceSpells(m)
							end, true)
						end
					end)
				end
				ns.Reparent(b, m.frame)
				b:SetFrameLevel(level)
				local scale = g[3] * k / b.wc3cNative
				ns.SetScale(b, scale)
				ns.ClearAllPoints(b)
				ns.SetPoint(b, "CENTER", m.frame, "BOTTOMLEFT", (g[1] + g[3] / 2 - m.rect[1]) * k / scale, (g[2] + g[4] / 2 - m.rect[2]) * k / scale)
				ns.StripButton(b)
				ns.MaskIcon(b)
			end
		end
	end)
	placing = false
end

ns.RegisterModule({
	key = "pet",
	label = "Pet",
	order = 66,
	level = 16,
	defaults = { spells = true },
	settings = {
		{ type = "toggle", key = "spells", label = "Pet action bar" },
	},
	Create = function(m)
		CreatePanel(m, "pet")
		m.spells = PetButtons()
		-- Blizzard's pet frame and pet bar are replaced
		local pf = _G.PetFrame
		ns.Reparent(pf, ns.hider)
		-- (on Forever Edit Mode puts the pet frame back in the frame of the
		-- class resources, shown over the portrait: hidden again, out of
		-- combat, the pet frame being protected)
		if pf then
			hooksecurefunc(pf, "SetParent", function(_, parent)
				if parent ~= ns.hider then
					ns.Defer("petframe-hide", function()
						ns.Reparent(pf, ns.hider)
					end, true)
				end
			end)
		end
		local bar = _G.PetActionBar or _G.PetActionBarFrame
		if bar then
			bar:SetAlpha(0)
			bar:EnableMouse(false)
		end
		local function Info()
			UpdateInfo(m)
		end
		ns.OnUnit("UNIT_PET", "player", Info)
		ns.On("PET_UI_UPDATE", Info)
		ns.On("PLAYER_ENTERING_WORLD", Info)
		ns.OnUnit("UNIT_NAME_UPDATE", "pet", Info)
		ns.OnUnit("UNIT_LEVEL", "pet", Info)
		local function Values()
			Update(m)
		end
		ns.OnUnit("UNIT_HEALTH", "pet", Values)
		ns.OnUnit("UNIT_MAXHEALTH", "pet", Values)
		ns.OnPower("pet", Values)
	end,
	Layout = function(m)
		local base = m.frame:GetFrameLevel()
		-- the window of the action bar: its back, the slots, its frame
		ns.Pieces(m, "window", { "pet_win" }, m.frame, base)
		ns.Pieces(m, "slots", { "pet_slots" }, m.frame, base + 1)
		ns.Pieces(m, "over", { "pet_over" }, m.frame, base + 6)
		LayoutPanel(m)
		if m.db.spells then
			PlaceSpells(m)
		else
			for _, b in ipairs(m.spells) do
				ns.Reparent(b, ns.hider)
			end
		end
	end,
})

------------------------------------------------------------------------
-- The pet of your target
------------------------------------------------------------------------

ns.RegisterModule({
	key = "targetpet",
	label = "Target's pet",
	order = 67,
	level = 46,
	Create = function(m)
		CreatePanel(m, "targetpet")
		local elapsed = 0
		m.frame:HookScript("OnUpdate", function(_, e)
			elapsed = elapsed + e
			if elapsed >= 0.2 then
				elapsed = 0
				local guid = UnitGUID("targetpet")
				if not ns.IsSecret(guid) and guid ~= m.lastGUID then
					m.lastGUID = guid
					UpdateInfo(m)
					SetPortraitTexture(m.portrait.tex, "targetpet")
				else
					Update(m)
				end
				ns.CastBarPoll(m.cast)
			end
		end)
		ns.On("PLAYER_TARGET_CHANGED", function()
			if m.frame:IsVisible() then
				UpdateInfo(m)
			end
		end)
	end,
	Layout = LayoutPanel,
})

