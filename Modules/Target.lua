--[[
	WC3 Console - target panel (shown with a target): round portrait in the
	retail target frame, elite / rare dragon and PvP flag on its ring, the
	name and level band coloured as Blizzard's, health / power, cast bar,
	combo points, auras; and the target of target.
]]

local _, ns = ...
local floor, max, min, format = math.floor, math.max, math.min, string.format
local R = ns.R
local IsSecret = ns.IsSecret

local GOLD = { 1, 0.82, 0 }

------------------------------------------------------------------------
-- Colours, as Blizzard's target frame (TargetFrameMixin:CheckFaction): the
-- band behind the name is grey when the unit is tapped by someone else
-- (and not a player's), else the colour of its selection circle
-- (UnitSelectionColor: red hostile, orange unfriendly, yellow neutral, green
-- friendly, blue player...); the portrait greyed with the tap. The level:
-- the difficulty colour when the target can be attacked, gold otherwise.
------------------------------------------------------------------------

local TYPE_ATLAS = "UI-HUD-UnitFrame-Target-PortraitOn-Type" -- (Blizzard's band)
-- by reaction, when the selection colour cannot be read
local REACTION_COLORS = { { 1, 0, 0 }, { 1, 0, 0 }, { 1, 0.5, 0 }, { 1, 1, 0 }, { 0, 1, 0 }, { 0, 1, 0 }, { 0, 1, 0 }, { 0, 1, 0 } }

local function LevelColor(unit)
	local canAttack = UnitCanAttack("player", unit)
	if IsSecret(canAttack) or not canAttack then
		return GOLD[1], GOLD[2], GOLD[3]
	end
	local c
	local P = C_PlayerInfo
	if P and P.GetContentDifficultyCreatureForPlayer and GetDifficultyColor then
		local ok, difficulty = pcall(P.GetContentDifficultyCreatureForPlayer, unit)
		if ok and difficulty ~= nil and not IsSecret(difficulty) then
			c = GetDifficultyColor(difficulty)
		end
	end
	if not c then
		local level = UnitLevel(unit)
		if not ns.Num(level) then
			return GOLD[1], GOLD[2], GOLD[3]
		elseif level <= 0 then
			return 1, 0.1, 0.1 -- (?? : far above you)
		end
		local fn = _G.GetCreatureDifficultyColor or _G.GetQuestDifficultyColor
		c = fn and fn(level)
	end
	if c then
		return c.r, c.g, c.b
	end
	return GOLD[1], GOLD[2], GOLD[3]
end

local function UpdateColors(m)
	if not UnitExists("target") then
		return
	end
	local tapped = UnitIsTapDenied("target")
	local controlled = UnitPlayerControlled("target")
	local grey = not IsSecret(tapped) and not IsSecret(controlled) and tapped and not controlled
	local band = m.band
	if grey then
		band:SetVertexColor(0.5, 0.5, 0.5)
	elseif not pcall(band.SetVertexColor, band, UnitSelectionColor("target")) then
		local reaction = UnitReaction("target", "player")
		local c = (not IsSecret(reaction) and REACTION_COLORS[reaction]) or REACTION_COLORS[4]
		band:SetVertexColor(c[1], c[2], c[3])
	end
	local v = grey and 0.5 or 1
	m.portrait.tex:SetVertexColor(v, v, v)
	m.level:SetTextColor(LevelColor("target"))
end

local function LevelText()
	local level = UnitLevel("target")
	return (ns.Num(level) and level > 0) and tostring(level) or "??"
end

------------------------------------------------------------------------
-- Elite / rare / boss: the dragon around the portrait (gold: elite,
-- silver: rare and rare elite, winged gold: boss), and the PvP flag on the
-- ring, as on Blizzard's modern target frame. The frame art is that
-- frame's texture (192 x 67) at 2x: its pieces go where Blizzard puts them,
-- measured from the top left corner of that texture (x right, y down),
-- scaled with it. (Blizzard's sizes: an atlas name can have a 2x twin on
-- this client, its own size made the dragon too big.)
------------------------------------------------------------------------

local DRAGONS = {
	-- atlas, its size, its top right corner
	boss = { "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold-Winged", 99, 81, 220, -8.5 },
	elite = { "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold", 80, 79, 201, -8.5 },
	rare = { "ui-hud-unitframe-target-portraiton-boss-rare-silver", 80, 79, 201, -8.5 },
}
-- the flags (atlas, its size): the middle of their top edge at FLAG_X, FLAG_Y
local FLAGS = {
	ffa = { "UI-HUD-UnitFrame-Player-PVP-FFAIcon", 28, 44 },
	Horde = { "UI-HUD-UnitFrame-Player-PVP-HordeIcon", 44, 44 },
	Alliance = { "UI-HUD-UnitFrame-Player-PVP-AllianceIcon", 28, 41 },
}
local FLAG_X, FLAG_Y = 186, 33.5
local FRAME_W = 192

local function DragonOf()
	local c = UnitClassification("target")
	if IsSecret(c) then
		return nil
	end
	local ok, boss = pcall(UnitIsBossMob, "target")
	if c == "worldboss" or (ok and boss == true) then
		return DRAGONS.boss
	elseif c == "elite" then
		return DRAGONS.elite
	elseif c == "rare" or c == "rareelite" then
		return DRAGONS.rare
	end
end

local function FlagOf()
	local ffa, pvp, faction = UnitIsPVPFreeForAll("target"), UnitIsPVP("target"), UnitFactionGroup("target")
	if IsSecret(ffa) or IsSecret(pvp) or IsSecret(faction) then
		return nil
	elseif ffa then
		return FLAGS.ffa
	elseif pvp then
		return FLAGS[faction]
	end
end

-- a piece (atlas, size) scaled with the frame art, its `point` at x, y
local function Mark(m, tex, a, x, y, point)
	if not (a and ns.HasAtlas(a[1])) then
		tex:Hide()
		return
	end
	local r = R.target
	local s = r[3] / FRAME_W
	tex:SetAtlas(a[1])
	ns.Place(tex, m, r[1] + x * s, r[2] + r[4] - y * s, a[2] * s, a[3] * s, point)
	tex:Show()
end

local function UpdateMarks(m)
	local d = DragonOf()
	Mark(m, m.dragon, d, d and d[4], d and d[5], "TOPRIGHT")
	Mark(m, m.flag, FlagOf(), FLAG_X, FLAG_Y, "TOP")
end

------------------------------------------------------------------------
-- Combo points: sockets + gems under the portrait (rogue, cat druid)
------------------------------------------------------------------------

local function ComboCount()
	local _, class = UnitClass("player")
	if not (class == "ROGUE" or (class == "DRUID" and UnitPowerType("player") == 3)) or not UnitExists("target") then
		return nil
	end
	local n = GetComboPoints and GetComboPoints("player", "target")
	if n == nil then
		n = UnitPower("player", 4)
	end
	if IsSecret(n) then
		return 0
	end
	return tonumber(n) or 0
end

local function UpdateCombo(m)
	local f = m.combo
	local n = ComboCount()
	if not n then
		f:Hide()
		f.shown = 0
		return
	end
	local was = f.shown or 0
	for i = 1, 5 do
		local g = f[i]
		if i <= n then
			if i > was then
				g:Show()
				g.pop:Stop()
				g.pop:Play()
			end
		else
			g:Hide()
		end
	end
	f.shown = n
	f:Show()
end

local function NewCombo(m)
	local f = CreateFrame("Frame", nil, m.frame)
	f:EnableMouse(false)
	f:SetAllPoints(m.frame)
	for i = 1, 5 do
		local g = CreateFrame("Frame", nil, f)
		g.tex = g:CreateTexture(nil, "ARTWORK")
		g.tex:SetAllPoints(g)
		g.tex:SetTexture(ns.Art("gem"))
		g.tex:SetTexCoord(0, 12 / 16, 0, 1)
		g.pop = g:CreateAnimationGroup()
		local a = g.pop:CreateAnimation("Alpha")
		a:SetFromAlpha(0)
		a:SetToAlpha(1)
		a:SetDuration(0.2)
		g:Hide()
		f[i] = g
	end
	f:Hide()
	f:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
	-- (Forever: the points moved to another unit keep their count, no power
	-- event then)
	pcall(f.RegisterEvent, f, "COMBO_TARGET_CHANGED")
	for _, e in ipairs({ "UNIT_POWER_FREQUENT", "UNIT_POWER_UPDATE", "UNIT_DISPLAYPOWER", "UNIT_MAXPOWER" }) do
		pcall(f.RegisterUnitEvent, f, e, "player")
	end
	f:SetScript("OnEvent", function(_, event, _, powerType)
		-- (power events: the combo points only)
		if (event == "UNIT_POWER_FREQUENT" or event == "UNIT_POWER_UPDATE") and powerType ~= "COMBO_POINTS" then
			return
		end
		UpdateCombo(m)
	end)
	m.combo = f
end

local function LayoutCombo(m)
	local f = m.combo
	f:SetFrameLevel(m.frame:GetFrameLevel() + 15)
	ns.Pieces(m, "sockets", { "sockets" }, f, f:GetFrameLevel())
	for i = 1, 5 do
		ns.PlaceRect(f[i], m, R["combo" .. i])
	end
	UpdateCombo(m)
end

------------------------------------------------------------------------
-- Auras, as on Blizzard's target frame, at its place and size (t_auras,
-- under the bars, TargetLayout.lua): the buffs in a row, the debuffs under
-- them (type colour border, stacks, time left). Three ways, by what the
-- client gives:
--   native  the engine aura container of Blizzard's (transparent) target
--           frame, laid under ours (PlaceTargetFrame): it shows the auras in
--           combat, where the aura APIs refuse addon code; Blizzard keeps
--           anchoring it, it is only made visible
--   blizz   Blizzard's own aura buttons moved into our slots after each of
--           its updates
--   own     our buttons, from the aura API (out of combat)
------------------------------------------------------------------------

local NATIVE_AURA = 21 -- (the size of Blizzard's aura buttons, UI units)
local AURA_ROWS = {
	{ filter = "HARMFUL", line = 2, font = 18, max = 8 },
	{ filter = "HELPFUL", line = 1, font = 16, max = 8 },
}
local DEBUFF_COLORS = { Magic = { 0.2, 0.6, 1 }, Curse = { 0.6, 0, 1 }, Disease = { 0.6, 0.4, 0 }, Poison = { 0, 0.6, 0 }, none = { 0.8, 0, 0 } }

-- slot j of a row: bottom left corner, size (art px). Blizzard's size, 3 UI
-- units apart; a row under the other, room left for the time left
local function Slot(row, j)
	local r, k = R.t_auras, ns.k
	local auraScale = min(1, k / .8)
	local size = NATIVE_AURA * auraScale / k
	local top = r[2] + r[4] - (row.line - 1) * (size + 14 * auraScale / k)
	return r[1] + (j - 1) * (size + 3 * auraScale / k), top - size, size
end

-- how many of a row t_auras holds
local function PerRow(row)
	local w, k = R.t_auras[3], ns.k
	local a = min(1, k / .8)
	return min(row.max, max(1, floor((w * k + 3 * a) / ((NATIVE_AURA + 3) * a))))
end

local function TimeText(s)
	if s >= 3600 then
		return format("%dh", floor(s / 3600 + 0.5))
	elseif s >= 60 then
		return format("%dm", floor(s / 60 + 0.5))
	elseif s >= 10 then
		return format("%d", floor(s + 0.5))
	end
	return format("%.1f", s)
end

local function ClearCooldown(cd)
	if cd.Clear then
		cd:Clear()
	else
		cd:SetCooldown(0, 0)
	end
end

local function AuraData(i, filter)
	if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		local ok, d = pcall(C_UnitAuras.GetAuraDataByIndex, "target", i, filter)
		return ok and d or nil
	end
	local ok, name, icon, count, kind, duration, expires = pcall(UnitAura, "target", i, filter)
	if ok and name then
		return { name = name, icon = icon, applications = count, dispelName = kind, duration = duration, expirationTime = expires }
	end
end

local function AuraEnter(self)
	if not self.index then
		return
	end
	local tt = GameTooltip
	tt:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
	if self.id and self.filter == "HARMFUL" and tt.SetUnitDebuffByAuraInstanceID then
		pcall(tt.SetUnitDebuffByAuraInstanceID, tt, "target", self.id, self.filter)
	elseif self.id and tt.SetUnitBuffByAuraInstanceID then
		pcall(tt.SetUnitBuffByAuraInstanceID, tt, "target", self.id, self.filter)
	else
		pcall(tt.SetUnitAura, tt, "target", self.index, self.filter)
	end
	tt:Show()
end

local function NewAuraButton(parent, row)
	local b = CreateFrame("Frame", nil, parent)
	b:EnableMouse(true)
	b.filter = row.filter
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints(b)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	b.cd:SetAllPoints(b)
	b.cd:SetReverse(true)
	b.cd:SetHideCountdownNumbers(true)
	local top = CreateFrame("Frame", nil, b)
	top:SetAllPoints(b)
	top:SetFrameLevel(b.cd:GetFrameLevel() + 2)
	top:EnableMouse(false)
	b.border = top:CreateTexture(nil, "OVERLAY")
	b.border:SetAllPoints(b)
	b.border:SetTexture(ns.Other("golden_frame"))
	b.count = ns.NewFont(top, row.font)
	ns.SetPoint(b.count, "BOTTOMRIGHT", b, "BOTTOMRIGHT", 1, 1)
	b.time = ns.NewFont(top, row.font)
	ns.SetPoint(b.time, "TOP", b, "BOTTOM", 0, -1)
	b:SetScript("OnEnter", AuraEnter)
	b:SetScript("OnLeave", GameTooltip_Hide)
	b:Hide()
	return b
end

local function SetAura(b, d, i)
	b.index, b.id, b.expires = i, d.auraInstanceID, nil
	b.icon:SetTexture(d.icon)
	-- border: the debuff type colour (debuffs), gold (buffs)
	if b.filter == "HARMFUL" then
		local kind = d.dispelName
		local c = (not IsSecret(kind) and kind and DEBUFF_COLORS[kind]) or DEBUFF_COLORS.none
		b.border:SetVertexColor(c[1], c[2], c[3])
	else
		b.border:SetVertexColor(1, 1, 1)
	end
	-- stacks
	local n = d.applications
	if IsSecret(n) then
		local ok, t = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, "target", d.auraInstanceID)
		b.count:SetText(ok and t or "")
	else
		b.count:SetText((n and n > 1) and n or "")
	end
	-- time left (secret: the duration object of the aura, its own countdown)
	local dur, exp = d.duration, d.expirationTime
	if IsSecret(dur) or IsSecret(exp) then
		b.time:SetText("")
		local ok, obj = false, nil
		if C_UnitAuras.GetAuraDuration and d.auraInstanceID then
			ok, obj = pcall(C_UnitAuras.GetAuraDuration, "target", d.auraInstanceID)
		end
		if ok and obj and b.cd.SetCooldownFromDurationObject then
			pcall(b.cd.SetCooldownFromDurationObject, b.cd, obj)
			b.cd:SetHideCountdownNumbers(false)
		else
			ClearCooldown(b.cd)
		end
	else
		b.cd:SetHideCountdownNumbers(true)
		if dur and exp and dur > 0 and exp > 0 then
			b.cd:SetCooldown(exp - dur, dur)
			b.expires = exp
			b.time:SetText(TimeText(max(0, exp - GetTime())))
		else
			ClearCooldown(b.cd)
			b.time:SetText("")
		end
	end
	b:Show()
end

-- Blizzard's aura buttons (debuffs, buffs, in order): in its target frame,
-- wherever it keeps them, and those already moved into our frame
local function IconOf(b)
	local i = b.Icon or b.icon or (b.GetName and b:GetName() and _G[b:GetName() .. "Icon"])
	return type(i) == "table" and i.GetObjectType and i
end

local function IsAuraButton(b)
	if not (b.GetObjectType and b.IsShown and b:IsShown() and IconOf(b)) then
		return false
	end
	local ok, big = pcall(function()
		return (b:GetWidth() or 0) * (b:GetScale() or 1) > 80
	end)
	if not ok or big then
		return false
	end
	local name = b.GetName and b:GetName()
	return (b.Cooldown or b.cooldown or b.auraInstanceID or b.unit or (name and (name:find("Buff") or name:find("Debuff")))) and true or false
end

local function IsDebuffButton(b)
	local name = b.GetName and b:GetName() or ""
	if name:find("Debuff") or b.isDebuff or b.isHarmful or b.Border or b.DebuffBorder or b.debuffBorder then
		return true
	end
	return b.filter ~= nil and tostring(b.filter):find("HARMFUL") ~= nil
end

local function ByID(x, y)
	local ok, less = pcall(function()
		return (x:GetID() or 0) < (y:GetID() or 0)
	end)
	return ok and less or false
end

local function BlizzAuras(m)
	local deb, buf, seen = {}, {}, {}
	local function Add(b)
		local list = IsDebuffButton(b) and deb or buf
		list[#list + 1] = b
	end
	local function Scan(fr, depth)
		if not fr or depth > 6 or seen[fr] then
			return
		end
		seen[fr] = true
		for _, c in ipairs({ fr:GetChildren() }) do
			if IsAuraButton(c) then
				Add(c)
			else
				Scan(c, depth + 1)
			end
		end
	end
	Scan(_G.TargetFrame, 0)
	for _, c in ipairs({ m.auras:GetChildren() }) do
		if c.wc3cAuraW and IsAuraButton(c) then
			Add(c)
		end
	end
	table.sort(deb, ByID)
	table.sort(buf, ByID)
	return deb, buf
end

local function PlaceBlizz(m, lists)
	local f, k = m.auras, ns.k
	for r, list in ipairs(lists) do
		local row = AURA_ROWS[r]
		for j, b in ipairs(list) do
			local shown = j <= PerRow(row)
			if shown then
				if b:GetParent() ~= f then
					b:SetParent(f)
				end
				if not b.wc3cAuraW then
					local w = b:GetWidth()
					b.wc3cAuraW = (w and w > 0) and w or NATIVE_AURA
				end
				local x, y, size = Slot(row, j)
				local scale = size * k / b.wc3cAuraW
				ns.SetScale(b, scale)
				ns.ClearAllPoints(b)
				ns.SetPoint(b, "BOTTOMLEFT", f, "BOTTOMLEFT", (x - m.rect[1]) * k / scale, (y - m.rect[2]) * k / scale)
				b:SetFrameLevel(f:GetFrameLevel() + 1)
				local cd = b.Cooldown or b.cooldown or (b:GetName() and _G[b:GetName() .. "Cooldown"])
				if cd and cd.SetHideCountdownNumbers then
					cd:SetHideCountdownNumbers(false)
				end
			end
			b:SetAlpha(shown and 1 or 0)
			b:EnableMouse(shown)
		end
	end
end

-- the engine container of Blizzard's target frame (TargetFrame > ... > Auras)
local function NativeAuras()
	local tf = _G.TargetFrame
	if not tf then
		return nil
	end
	local c = tf.TargetFrameContent
	c = c and c.TargetFrameContentContextual
	if c and c.Auras then
		return c.Auras
	end
	if tf.Auras then
		return tf.Auras
	end
	local found
	local function Walk(fr, depth)
		if found or depth > 4 then
			return
		end
		for _, kid in ipairs({ fr:GetChildren() }) do
			if type(kid.Auras) == "table" and kid.Auras.GetObjectType then
				found = kid.Auras
				return
			end
			Walk(kid, depth + 1)
		end
	end
	Walk(tf, 0)
	return found
end

local function PlaceNative(m)
	local au = m.nativeAuras
	if au:IsProtected() and InCombatLockdown() then
		ns.RunOOC("targetauras", function()
			PlaceNative(m)
		end)
		return
	end
	ns.Try("target native auras", function()
		-- (its place and size are Blizzard's: the frame is under ours)
		if au.SetIgnoreParentAlpha then
			au:SetIgnoreParentAlpha(true)
		end
		au:SetAlpha(1)
		au:SetShown(m.db.auras)
	end)
end

------------------------------------------------------------------------
-- Blizzard's target frame (transparent, without mouse: Blizzard.lua) laid
-- exactly under our panel, at the size of our art (TargetLayout.lua): its
-- auras and its cast bar show at their original place, and Blizzard moves
-- them itself (the cast bar goes under the target of target or the aura
-- rows). Out of combat only (a protected frame), placed again when edit
-- mode moves it.
------------------------------------------------------------------------

local function PlaceTargetFrame(m)
	local tf, L = _G.TargetFrame, ns.TARGET_FRAME
	if not (tf and L) then
		return
	end
	ns.RunOOC("target-blizzard-frame", function()
		ns.Try("target frame placement", function()
			local s = L.unit * ns.k
			if math.abs((tf:GetScale() or 1) - s) > 0.0001 then
				ns.SetScale(tf, s)
			end
			ns.Follow(m, tf, "TOPLEFT", L.x, L.y)
		end)
	end)
end

-- Blizzard's cast bar of the target: shown through the transparent frame
-- (ours is used only when the client has none)
local function ShowBlizzardCastBar(m)
	local bar = _G.TargetFrame and _G.TargetFrame.spellbar
	if not (bar and bar.SetIgnoreParentAlpha) then
		return false
	end
	bar:SetIgnoreParentAlpha(m.db.castBar and true or false)
	return true
end

local function UpdateAuras(m)
	local f = m.auras
	if not (m.db.auras and UnitExists("target")) then
		f:Hide()
		return
	end
	f:Show()
	if f.mode == "native" then
		return
	end
	if f.mode == "blizz" then
		local deb, buf = BlizzAuras(m)
		if #deb + #buf > 0 then
			for _, row in ipairs(f.rows) do
				for _, b in ipairs(row) do
					b:Hide()
				end
			end
			PlaceBlizz(m, { deb, buf })
			return
		end
	end
	for r, row in ipairs(AURA_ROWS) do
		local n = 0
		for i = 1, 40 do
			if n >= PerRow(row) then
				break
			end
			local d = AuraData(i, row.filter)
			if not d then
				break
			end
			n = n + 1
			SetAura(f.rows[r][n], d, i)
		end
		for j = n + 1, row.max do
			f.rows[r][j]:Hide()
			f.rows[r][j].index = nil
		end
	end
end

local function NewAuras(m)
	local f = CreateFrame("Frame", nil, m.frame)
	f:SetAllPoints(m.frame)
	f:EnableMouse(false)
	f.rows = {}
	for r, row in ipairs(AURA_ROWS) do
		f.rows[r] = {}
		for j = 1, row.max do
			f.rows[r][j] = NewAuraButton(f, row)
		end
	end
	m.auras = f
	local function Update()
		UpdateAuras(m)
	end
	ns.OnUnit("UNIT_AURA", "target", Update)
	-- the time left, 10 times a second
	local acc = 0
	f:SetScript("OnUpdate", function(self, e)
		if self.mode == "native" then return end
		acc = acc + e
		if acc < 0.1 then
			return
		end
		acc = 0
		local now = GetTime()
		for _, row in ipairs(self.rows) do
			for _, b in ipairs(row) do
				if b.expires and b:IsShown() then
					b.time:SetText(TimeText(max(0, b.expires - now)))
				end
			end
		end
	end)
	-- the way: the native container, else Blizzard's buttons, else ours
	local au = NativeAuras()
	local tf = _G.TargetFrame
	if au then
		f.mode = "native"
		m.nativeAuras = au
		-- (Blizzard anchors and sizes it: only its visibility is ours)
		local function Again()
			ns.Defer("target-native-auras", function()
				PlaceNative(m)
			end, true)
		end
		if au.SetIgnoreParentAlpha then
			hooksecurefunc(au, "SetIgnoreParentAlpha", function(_, v)
				if not v then
					Again()
				end
			end)
		end
	elseif tf and (tf.UpdateAuras or _G.TargetFrame_UpdateAuras) then
		f.mode = "blizz"
		for _, name in ipairs({ "UpdateAuras", "UpdateAuraPositions" }) do
			if tf[name] then
				hooksecurefunc(tf, name, Update)
			end
			if _G["TargetFrame_" .. name] then
				hooksecurefunc("TargetFrame_" .. name, Update)
			end
		end
	else
		f.mode = "own"
	end
end

local function LayoutAuras(m)
	local f = m.auras
	f:SetFrameLevel(m.frame:GetFrameLevel() + 14)
	for r, row in ipairs(AURA_ROWS) do
		for j, b in ipairs(f.rows[r]) do
			local x, y, size = Slot(row, j)
			ns.Place(b, m, x, y, size, size)
		end
	end
	if f.mode == "native" then
		PlaceNative(m)
	end
	UpdateAuras(m)
end

-- /wc3c auras: what this client gives for the target auras
function ns.AuraDebug()
	local m = ns.Enabled("target")
	if not m then
		return
	end
	local deb, buf = BlizzAuras(m)
	local tf = _G.TargetFrame
	ns.Print(format("target auras: %s; Blizzard's buttons: %d debuffs, %d buffs; target frame shown %s; combat %s",
		m.auras.mode, #deb, #buf, tostring(tf and tf:IsShown()), tostring(InCombatLockdown())))
end

------------------------------------------------------------------------
-- Target module
------------------------------------------------------------------------

local function Update(m)
	local exists = UnitExists("target")
	m.dyn:SetShown(exists)
	ns.CastBarRefresh(m.cast)
	UpdateCombo(m)
	UpdateAuras(m)
	if not exists then
		return
	end
	ns.UpdateUnitName(m)
	m.level:SetText(LevelText())
	if not m.health.wc3cAtlas then
		m.health:SetStatusBarColor(ns.ReactionColor("target"))
	end
	ns.UpdateUnitHealth(m)
	ns.UpdateUnitPower(m)
	UpdateColors(m)
	UpdateMarks(m)
end

-- (frame levels above Blizzard's target frame, 500 and its children,
-- which lies under the panel: our panel keeps the mouse)
ns.RegisterModule({
	key = "target",
	label = "Target",
	order = 50,
	level = 600,
	defaults = { castBar = true, auras = true, percent = false },
	settings = {
		{ type = "toggle", key = "castBar", label = "Cast bar" },
		{ type = "toggle", key = "auras", label = "Buffs / debuffs" },
		{ type = "toggle", key = "percent", label = "Health in percent" },
	},
	Create = function(m)
		local f = m.frame
		local base = f:GetFrameLevel()
		m.unit = "target"
		-- what is shown with a target
		local dyn = CreateFrame("Frame", nil, f)
		dyn:SetFrameLevel(base + 4)
		dyn:SetAllPoints(f)
		m.dyn = dyn
		m.portrait = ns.NewPortrait(dyn, "target")
		m.portrait:SetFrameLevel(base + 2)
		-- the dragon and the flag over the ring of the frame art (+3)
		local marks = CreateFrame("Frame", nil, dyn)
		marks:SetFrameLevel(base + 4)
		marks:SetAllPoints(f)
		marks:EnableMouse(false)
		m.dragon = marks:CreateTexture(nil, "ARTWORK")
		m.flag = marks:CreateTexture(nil, "OVERLAY")
		-- the band over the name and level
		local band = CreateFrame("Frame", nil, dyn)
		band:SetFrameLevel(base + 5)
		band:EnableMouse(false)
		m.bandFrame = band
		m.band = band:CreateTexture(nil, "ARTWORK")
		m.band:SetAllPoints(band)
		if ns.HasAtlas(TYPE_ATLAS) then
			m.band:SetAtlas(TYPE_ATLAS)
		else
			m.band:SetTexture([[Interface\Buttons\WHITE8X8]])
		end
		m.button = ns.UnitButton("WC3C_targetUnitButton", f, "target", base + 12)
		m.health = ns.NewBar(dyn, base + 5, "TARGET_HEALTH")
		m.power = ns.NewBar(dyn, base + 6, "MANA")
		local texts = CreateFrame("Frame", nil, dyn)
		texts:SetFrameLevel(base + 9)
		texts:SetAllPoints(f)
		m.healthText = ns.NewFont(texts, 15)
		m.powerText = ns.NewFont(texts, 10)
		m.name = ns.NewFont(texts, 20)
		-- the level alone at the right end of the band (the retail frame has
		-- room for the number only)
		m.level = ns.NewFont(texts, 15)
		m.level:SetJustifyH("RIGHT")
		m.cast = ns.NewCastBar(m, "target", base + 8, "castT")
		NewCombo(m)
		NewAuras(m)
		ns.WatchName(m)
		ns.HookPosition(_G.TargetFrame, function()
			PlaceTargetFrame(m)
		end)

		local function All()
			Update(m)
		end
		ns.On("PLAYER_TARGET_CHANGED", All)
		ns.On("PLAYER_ENTERING_WORLD", All)
		for _, e in ipairs({ "UNIT_LEVEL", "UNIT_FACTION", "UNIT_CLASSIFICATION_CHANGED" }) do
			ns.OnUnit(e, "target", All)
		end
		local function Health()
			ns.UpdateUnitHealth(m)
		end
		ns.OnUnit("UNIT_HEALTH", "target", Health)
		ns.OnUnit("UNIT_MAXHEALTH", "target", Health)
		ns.OnPower("target", function()
			ns.UpdateUnitPower(m)
		end)
		-- (the level colour follows yours, the tap your group)
		local function Colors()
			UpdateColors(m)
		end
		ns.On("GROUP_ROSTER_UPDATE", Colors)
		ns.On("PLAYER_LEVEL_UP", Colors)
		ns.OnUnit("UNIT_FACTION", "player", Colors)
	end,
	Layout = function(m)
		local base = m.frame:GetFrameLevel()
		ns.PlaceRect(m.portrait, m, R.t_portrait)
		ns.Pieces(m, "front", { "t_frame" }, m.dyn, base + 3)
		ns.PlaceRect(m.button, m, R.target)
		local n, l = R.t_name, R.t_lvl
		ns.PlaceRect(m.bandFrame, m, { n[1], n[2], l[1] + l[3] - n[1], n[4] })
		ns.LayoutName(m, n, 20)
		ns.Place(m.level, m, l[1] + l[3], l[2] + l[4] / 2, nil, nil, "RIGHT")
		ns.PlaceRect(m.health, m, R.t_health)
		ns.PlaceRect(m.power, m, R.t_power)
		ns.TextOnBar(m.healthText, m.health)
		ns.TextOnBar(m.powerText, m.power)
		PlaceTargetFrame(m)
		local blizzardCast = ShowBlizzardCastBar(m)
		m.cast.enabled = m.db.castBar and not blizzardCast
		ns.LayoutCastBar(m.cast, m, R.t_cast)
		LayoutCombo(m)
		LayoutAuras(m)
		Update(m)
	end,
})

------------------------------------------------------------------------
-- Target of target: a small panel (round portrait, health, name) shown by
-- the unit watch of its secure button; no events for this unit: refreshed
-- 5 times a second
------------------------------------------------------------------------

local function UpdateToT(m)
	if not UnitExists("targettarget") then
		return
	end
	local cur, maxHP = UnitHealth("targettarget"), UnitHealthMax("targettarget")
	m.health:SetMinMaxValues(0, maxHP)
	m.health:SetValue(cur)
	if not m.health.wc3cAtlas then
		pcall(m.health.SetStatusBarColor, m.health, ns.ReactionColor("targettarget"))
	end
	pcall(m.name.SetText, m.name, ns.UnitDisplayName("targettarget"))
end

-- Shown when Blizzard's own target of target is (it lies under ours: not
-- when you target yourself, nor a dead target, nor with Blizzard's option
-- off). Blizzard moves its cast bar under the target of target and narrows
-- its aura rows only for its own: ours then never covers them. (Our secure
-- button keeps its unit watch, it is only made transparent, its tooltip
-- skipped; a click on it targets the unit you already target.)
local function BlizzardToT()
	local tf = _G.TargetFrame
	return tf and tf.totFrame
end

local function UpdateToTShown(m)
	local blizz = BlizzardToT()
	local shown = not blizz or blizz:IsShown() and true or false
	if m.shown ~= shown then
		m.shown = shown
		m.button:SetAlpha(shown and 1 or 0)
	end
end

-- (above Blizzard's target of target, 505, laid under it)
ns.RegisterModule({
	key = "targettarget",
	label = "Target of target",
	order = 55,
	level = 610,
	Create = function(m)
		local f = m.frame
		local base = f:GetFrameLevel()
		m.unit = "targettarget"
		-- (everything hangs on the button: hidden with it)
		local b = ns.UnitButton("WC3C_TargetTargetButton", f, "targettarget", base + 1)
		b:SetAllPoints(f)
		RegisterUnitWatch(b)
		m.button = b
		m.portrait = ns.NewPortrait(b, "targettarget")
		m.portrait:SetFrameLevel(base + 2)
		m.health = ns.NewBar(b, base + 4, "TARGET_HEALTH")
		local texts = CreateFrame("Frame", nil, b)
		texts:SetFrameLevel(base + 7)
		texts:SetAllPoints(f)
		m.name = ns.NewFont(texts, 12)
		local function Refresh()
			UpdateToTShown(m)
			pcall(UpdateToT, m)
		end
		b:HookScript("OnShow", Refresh)
		ns.On("PLAYER_TARGET_CHANGED", Refresh)
		ns.OnUnit("UNIT_TARGET", "target", Refresh)
		local blizz = BlizzardToT()
		if blizz then
			blizz:HookScript("OnShow", Refresh)
			blizz:HookScript("OnHide", Refresh)
		end
		local enter = b:GetScript("OnEnter")
		b:SetScript("OnEnter", function(self)
			if m.shown ~= false and enter then
				enter(self)
			end
		end)
		local elapsed = 0
		b:HookScript("OnUpdate", function(_, e)
			elapsed = elapsed + e
			if elapsed >= 0.2 then
				elapsed = 0
				Refresh()
			end
		end)
	end,
	Layout = function(m)
		ns.PlaceRect(m.portrait, m, R.tot_portrait)
		ns.Pieces(m, "front", { "tot_frame" }, m.button, m.button:GetFrameLevel() + 2)
		ns.PlaceRect(m.health, m, R.tot_health)
		ns.CenterText(m.name, m, R.tot_name)
		UpdateToTShown(m)
		pcall(UpdateToT, m)
	end,
})
