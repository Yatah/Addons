--[[
	WC3 Console - what the unit panels share (player, target, target of
	target, pets): health / power bars, values, names, round portraits,
	click zones, cast bars.
]]

local _, ns = ...
local max, min = math.max, math.min

------------------------------------------------------------------------
-- Health / power bars: the retail unit frame bars (atlases of the modern
-- client), slightly aged: a bit desaturated, shaded from the top (light)
-- to the bottom (dark), on a dark trough. Classic bar texture when the
-- client has no such atlas.
------------------------------------------------------------------------

local BAR_ATLAS = {
	PLAYER_HEALTH = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health",
	TARGET_HEALTH = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health",
	MANA = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana",
	RAGE = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Rage",
	ENERGY = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Energy",
	FOCUS = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Focus",
	RUNIC_POWER = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-RunicPower",
}
local BAR_FALLBACK = [[Interface\TargetingFrame\UI-StatusBar]]
local BAR_COLORS = {
	PLAYER_HEALTH = { 0, 0.8, 0 },
	TARGET_HEALTH = { 0, 0.8, 0 },
	MANA = { 0, 0.35, 1 },
	RAGE = { 1, 0, 0 },
	ENERGY = { 1, 1, 0 },
	FOCUS = { 1, 0.5, 0.25 },
	RUNIC_POWER = { 0, 0.82, 1 },
	REPUTATION = { 0, 0.6, 0.1 }, -- (no atlas: coloured by its standing)
}

function ns.HasAtlas(name)
	return name and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil or false
end

-- kind: key of BAR_ATLAS / BAR_COLORS; color: fallback colour ({ r, g, b }
-- fields)
function ns.SetBarLook(bar, kind, color)
	if bar.wc3cKind == kind then
		return
	end
	bar.wc3cKind = kind
	local atlas = BAR_ATLAS[kind]
	local ok = ns.HasAtlas(atlas) and pcall(bar.SetStatusBarTexture, bar, atlas)
	bar.wc3cAtlas = ok and true or false
	if ok then
		bar:SetStatusBarColor(1, 1, 1, 1)
	else
		bar:SetStatusBarTexture(BAR_FALLBACK)
		local c = BAR_COLORS[kind]
		if color then
			bar:SetStatusBarColor(color.r, color.g, color.b, 1)
		elseif c then
			bar:SetStatusBarColor(c[1], c[2], c[3], 1)
		end
	end
	local fill = bar:GetStatusBarTexture()
	if fill then
		if fill.SetDesaturation then
			pcall(fill.SetDesaturation, fill, 0.25)
		end
		fill:SetDrawLayer("ARTWORK", 0)
		ns.ClearAllPoints(bar.wc3cShade)
		bar.wc3cShade:SetAllPoints(fill)
		ns.ClearAllPoints(bar.wc3cGloss)
		ns.SetPoint(bar.wc3cGloss, "TOPLEFT", fill, "TOPLEFT", 0, 0)
		ns.SetPoint(bar.wc3cGloss, "TOPRIGHT", fill, "TOPRIGHT", 0, 0)
	end
end

function ns.NewBar(parent, level, kind)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetFrameLevel(level)
	local trough = bar:CreateTexture(nil, "BACKGROUND")
	trough:SetAllPoints(bar)
	trough:SetColorTexture(0.05, 0.04, 0.03, 0.9)
	-- shading of the filled part only (it follows the value)
	local shade = bar:CreateTexture(nil, "ARTWORK", nil, 3)
	shade:SetTexture([[Interface\Buttons\WHITE8X8]])
	shade:SetVertexColor(0, 0, 0, 0.25)
	pcall(shade.SetGradient, shade, "VERTICAL", CreateColor(0, 0, 0, 0.45), CreateColor(1, 0.95, 0.8, 0.10))
	bar.wc3cShade = shade
	-- a thin light line along the top edge
	local gloss = bar:CreateTexture(nil, "ARTWORK", nil, 4)
	gloss:SetColorTexture(1, 0.95, 0.8, 0.18)
	gloss:SetHeight(1)
	bar.wc3cGloss = gloss
	ns.SetBarLook(bar, kind)
	return bar
end

function ns.ReactionColor(unit)
	if UnitIsPlayer(unit) then
		local _, class = UnitClass(unit)
		local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
		if c then
			return c.r, c.g, c.b
		end
	end
	local reaction = UnitReaction(unit, "player")
	local c = reaction and FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
	if c then
		return c.r, c.g, c.b
	end
	return 1, 0.82, 0
end

-- "cur / max" (percent above 99999, or when asked), secret values too
function ns.SetValueText(fs, cur, maxV, percent)
	if ns.IsSecret(cur) or ns.IsSecret(maxV) then
		pcall(fs.SetFormattedText, fs, "%s / %s", cur, maxV)
	elseif type(cur) ~= "number" or type(maxV) ~= "number" then
		fs:SetText("")
	elseif percent or maxV > 99999 then
		fs:SetFormattedText("%.0f%%", maxV > 0 and cur / maxV * 100 or 0)
	else
		fs:SetText(cur .. " / " .. maxV)
	end
end

-- health of m.unit on m.health (+ m.healthText); returns its ratio when
-- it can be read
function ns.UpdateUnitHealth(m)
	local unit = m.unit
	local cur, maxHP = UnitHealth(unit), UnitHealthMax(unit)
	m.health:SetMinMaxValues(0, maxHP)
	m.health:SetValue(cur)
	if m.healthText then
		ns.SetValueText(m.healthText, cur, maxHP, m.db.percent)
		-- A zero/current number must not hide these unit states.
		local connected = UnitIsConnected and UnitIsConnected(unit)
		local dead = UnitIsDead and UnitIsDead(unit)
		local ghost = UnitIsGhost and UnitIsGhost(unit)
		if not ns.IsSecret(connected) and connected == false then
			m.healthText:SetText(_G.PLAYER_OFFLINE or "Offline")
		elseif not ns.IsSecret(ghost) and ghost == true then
			m.healthText:SetText(_G.GHOST or "Ghost")
		elseif not ns.IsSecret(dead) and dead == true then
			m.healthText:SetText(_G.DEAD or "Dead")
		end
	end
	if ns.Num(cur) and ns.Num(maxHP) then
		return maxHP > 0 and cur / maxHP or 0
	end
end

-- (UNIT_POWER_FREQUENT: every tick, smooth energy / rage; the older event
-- when the client lacks it)
function ns.OnPower(unit, fn)
	if not ns.OnUnit("UNIT_POWER_FREQUENT", unit, fn) then
		ns.OnUnit("UNIT_POWER_UPDATE", unit, fn)
	end
	ns.OnUnit("UNIT_MAXPOWER", unit, fn)
	ns.OnUnit("UNIT_DISPLAYPOWER", unit, fn)
end

function ns.MaxLevel()
	local fn = _G.GetMaxLevelForPlayerExpansion or _G.GetMaxPlayerLevel
	local ok, lvl = pcall(fn)
	return (ok and ns.Num(lvl) and lvl > 0) and lvl or 60
end

-- The watched faction (Reputation panel: "Show as experience bar"): name,
-- standing (1 hated .. 8 exalted), bounds of the standing, value; nothing
-- when none is watched. C_Reputation on the modern clients, the older
-- function otherwise (or when the modern one fails).
function ns.WatchedFaction()
	local get = C_Reputation and C_Reputation.GetWatchedFactionData
	if get then
		local ok, d = pcall(get)
		if ok then
			if type(d) == "table" and d.name then
				return d.name, d.reaction, d.currentReactionThreshold, d.nextReactionThreshold, d.currentStanding
			end
			return
		end
	end
	if GetWatchedFactionInfo then
		local ok, name, standing, low, high, value = pcall(GetWatchedFactionInfo)
		if ok and name then
			return name, standing, low, high, value
		end
	end
end

-- power of m.unit on m.power (+ m.powerText); the bar hidden without power
function ns.UpdateUnitPower(m)
	local unit = m.unit
	local powerType, token = UnitPowerType(unit)
	ns.SetBarLook(m.power, token or "MANA", PowerBarColor and (PowerBarColor[token] or PowerBarColor[powerType]))
	local cur, maxP = UnitPower(unit, powerType), UnitPowerMax(unit, powerType)
	m.power:SetMinMaxValues(0, maxP)
	m.power:SetValue(cur)
	local has = not ns.Num(maxP) or maxP > 0
	if has ~= m.hasPower then
		m.hasPower = has
		m.power:SetShown(has)
	end
	if m.powerText then
		if has then
			ns.SetValueText(m.powerText, cur, maxP, m.db.percent)
		else
			m.powerText:SetText("")
		end
	end
end

------------------------------------------------------------------------
-- Names: as the Blizzard unit frames show them (WoW Forever names can be
-- made of several parts), UnitName otherwise
------------------------------------------------------------------------

local function BlizzardNameText(unit)
	if unit == "player" then
		local pf = _G.PlayerFrame
		local content = pf and pf.PlayerFrameContent
		content = content and content.PlayerFrameContentMain
		return _G.PlayerName or (pf and pf.name) or (content and content.Name)
	elseif unit == "target" then
		local tf = _G.TargetFrame
		local content = tf and tf.TargetFrameContent
		content = content and content.TargetFrameContentMain
		return (tf and tf.name) or _G.TargetFrameTextureFrameName or (content and content.Name)
	end
end

function ns.UnitDisplayName(unit)
	local fs = BlizzardNameText(unit)
	if fs and fs.GetText then
		local ok, text = pcall(fs.GetText, fs)
		if ok and text ~= nil and (ns.IsSecret(text) or text ~= "") then
			return text
		end
	end
	local ok, text = pcall(GetUnitName, unit, true)
	if ok and text then
		return text
	end
	return UnitName(unit)
end

-- the name fits its band (m.nameW art px): from m.nameSize down to 11 px,
-- Blizzard's gold (the reaction colour is the band behind it)
local function FitName(m)
	local k, w = ns.k, m.nameW
	for size = m.nameSize, 11, -1 do
		m.name:SetFont(ns.FONT, size * k, "OUTLINE")
		local ok, sw = pcall(m.name.GetStringWidth, m.name)
		if not ok or not ns.Num(sw) or sw <= (w - 8) * k then
			break
		end
	end
end

function ns.UpdateUnitName(m)
	if UnitExists(m.unit) then
		m.name:SetText(ns.UnitDisplayName(m.unit))
		FitName(m)
	end
end

-- a name fitted in the rect r, from `size` px down
function ns.LayoutName(m, r, size)
	m.nameW, m.nameSize = r[3], size
	ns.CenterText(m.name, m, r)
	m.name:SetTextColor(1, 0.82, 0)
	ns.UpdateUnitName(m)
end

-- Blizzard's name is read once its own update is done (next frame): its
-- SetText stays untouched, it is called from the protected unit frame path
function ns.WatchName(m)
	local unit = m.unit
	local function Refresh()
		ns.Defer("unit-name-" .. unit, function()
			ns.UpdateUnitName(m)
		end)
	end
	ns.OnUnit("UNIT_NAME_UPDATE", unit, Refresh)
	ns.On("PLAYER_ENTERING_WORLD", Refresh)
	if unit == "target" then
		ns.On("PLAYER_TARGET_CHANGED", Refresh)
	end
end

------------------------------------------------------------------------
-- Round portraits (Blizzard's portrait textures are round already) and
-- secure click zones (left click: target, right click: the unit menu)
------------------------------------------------------------------------

function ns.NewPortrait(parent, unit)
	local f = CreateFrame("Frame", nil, parent)
	f:EnableMouse(false)
	f.tex = f:CreateTexture(nil, "ARTWORK")
	f.tex:SetAllPoints(f)
	f.unit = unit
	f.Update = function(self)
		if UnitExists(self.unit) then
			pcall(SetPortraitTexture, self.tex, self.unit)
		end
	end
	-- (its own events; the compound units change with the target, its
	-- target, the pet)
	f:RegisterUnitEvent("UNIT_PORTRAIT_UPDATE", unit)
	f:RegisterUnitEvent("UNIT_MODEL_CHANGED", unit)
	f:RegisterEvent("PLAYER_TARGET_CHANGED")
	f:RegisterUnitEvent("UNIT_TARGET", "target")
	f:RegisterUnitEvent("UNIT_PET", "player")
	f:SetScript("OnEvent", f.Update)
	f:SetScript("OnShow", f.Update)
	return f
end

local function UnitEnter(self)
	if UnitExists(self.unit) and UnitFrame_OnEnter then
		UnitFrame_OnEnter(self)
	end
end

local function UnitLeave(self)
	if UnitFrame_OnLeave then
		UnitFrame_OnLeave(self)
	else
		GameTooltip:Hide()
	end
end

function ns.UnitButton(name, parent, unit, level)
	local b = CreateFrame("Button", name, parent, "SecureUnitButtonTemplate")
	b:SetFrameLevel(level)
	b.unit = unit
	b:SetAttribute("unit", unit)
	b:SetAttribute("*type1", "target")
	b:SetAttribute("*type2", "togglemenu")
	b:RegisterForClicks("AnyUp")
	b:SetScript("OnEnter", UnitEnter)
	b:SetScript("OnLeave", UnitLeave)
	return b
end

------------------------------------------------------------------------
-- Cast bars
--   textured (player, target): the retail cast bar, a fill per kind of cast
--   flat (pets): a fill coloured by the kind of cast
-- The timer comes from the duration object when the cast times are secret.
-- Events of the unit only; the target's pet has no unit events: polled.
------------------------------------------------------------------------

local CAST_LOOK = {
	cast = { 1, 0.7, 0, "castfill" },
	channel = { 0, 1, 0, "castchan" },
	shield = { 0.6, 0.6, 0.6, "castshield" },
	failed = { 1, 0, 0, "castfail" },
	done = { 0, 1, 0, "castchan" },
}

local function SetCastLook(cb, key)
	if cb.look == key then
		return
	end
	cb.look = key
	local c = CAST_LOOK[key]
	if cb.textured then
		cb.bar:SetStatusBarTexture(ns.Art(c[4]))
	else
		cb.bar:SetStatusBarColor(c[1], c[2], c[3], 1)
	end
end

local function CastUpdate(frame, elapsed)
	local cb = frame.cb
	if cb.casting then
		if cb.start then
			local now = GetTime()
			local total = cb.finish - cb.start
			local v = cb.channel and (cb.finish - now) / total or (now - cb.start) / total
			cb.bar:SetValue(max(0, min(1, v)))
			if cb.time then
				cb.time:SetFormattedText("%.1f", max(0, cb.finish - now))
			end
			if now >= cb.finish + 0.3 then
				ns.CastBarStop(cb, not cb.channel and "done" or nil)
			end
		end
	elseif cb.fadeOut then
		cb.fadeOut = cb.fadeOut - elapsed
		frame:SetAlpha(min(1, max(0, cb.fadeOut / 0.4)))
		if cb.fadeOut <= 0 then
			cb.fadeOut = nil
			frame:SetAlpha(0)
			frame:SetScript("OnUpdate", nil)
		end
	else
		frame:SetScript("OnUpdate", nil)
	end
end

function ns.CastBarStart(cb, channel)
	local unit = cb.unit
	local name, startMS, endMS, notInterruptible, _
	if channel then
		name, _, _, startMS, endMS, _, notInterruptible = UnitChannelInfo(unit)
	else
		name, _, _, startMS, endMS, _, _, notInterruptible = UnitCastingInfo(unit)
	end
	if not name then
		return false
	end
	cb.casting, cb.channel, cb.fadeOut = true, channel, nil
	cb.text:SetText(name)
	if ns.Num(startMS) and ns.Num(endMS) and endMS > startMS then
		cb.start, cb.finish = startMS / 1000, endMS / 1000
	else
		cb.start, cb.finish = nil, nil
		cb.bar:SetValue(1)
		if cb.time then
			cb.time:SetText("")
		end
		local durationFn = channel and _G.UnitChannelDuration or _G.UnitCastingDuration
		if durationFn and cb.bar.SetTimerDuration then
			local ok, duration = pcall(durationFn, unit)
			if ok and duration then
				local E = _G.Enum
				local dir = E and E.StatusBarTimerDirection
					and (channel and E.StatusBarTimerDirection.RemainingTime or E.StatusBarTimerDirection.ElapsedTime)
				local interp = E and E.StatusBarInterpolation and E.StatusBarInterpolation.Immediate
				pcall(cb.bar.SetTimerDuration, cb.bar, duration, interp, dir)
			end
		end
	end
	if unit ~= "player" and not ns.IsSecret(notInterruptible) and notInterruptible then
		SetCastLook(cb, "shield")
	else
		SetCastLook(cb, channel and "channel" or "cast")
	end
	cb.frame:SetAlpha(1)
	cb.frame:SetScript("OnUpdate", CastUpdate)
	return true
end

function ns.CastBarStop(cb, key, text)
	if not cb.casting and not text then
		return
	end
	cb.casting = false
	if key then
		SetCastLook(cb, key)
		cb.bar:SetValue(1)
	end
	if text then
		cb.text:SetText(text)
	end
	if cb.time then
		cb.time:SetText("")
	end
	cb.fadeOut = key == "failed" and 1.0 or 0.4
	cb.frame:SetScript("OnUpdate", CastUpdate)
end

function ns.CastBarRefresh(cb)
	if not (cb.enabled and UnitExists(cb.unit) and (ns.CastBarStart(cb, true) or ns.CastBarStart(cb, false))) then
		cb.casting, cb.fadeOut = false, nil
		cb.frame:SetAlpha(0)
		cb.frame:SetScript("OnUpdate", nil)
	end
end

-- (a unit without events: started / stopped from what it casts now)
function ns.CastBarPoll(cb)
	local casting = UnitCastingInfo(cb.unit) or UnitChannelInfo(cb.unit)
	if casting and not cb.casting then
		ns.CastBarRefresh(cb)
	elseif not casting and cb.casting then
		ns.CastBarStop(cb, not cb.channel and "done" or nil)
	end
end

local function OnCast(cb, event, unit)
	if not cb.enabled then
		return
	end
	if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_DELAYED" then
		ns.CastBarStart(cb, false)
	elseif event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
		ns.CastBarStart(cb, true)
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_STOP" then
		if cb.casting and not cb.channel then
			ns.CastBarStop(cb, "done")
		end
	elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" or event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
		if cb.casting then
			SetCastLook(cb, event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" and "shield" or (cb.channel and "channel" or "cast"))
		end
	elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
		if cb.casting and cb.channel then
			ns.CastBarStop(cb, nil)
		end
	elseif cb.casting and not UnitCastingInfo(unit) and not UnitChannelInfo(unit) then
		-- interrupted / failed
		ns.CastBarStop(cb, "failed", event == "UNIT_SPELLCAST_INTERRUPTED" and (INTERRUPTED or "Interrupted") or (FAILED or "Failed"))
	end
end

local CAST_EVENTS = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE",
	"UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" }

-- textured: the art key ("castP", "castT") of the retail cast bar
function ns.NewCastBar(m, unit, level, textured)
	local cb = { unit = unit, enabled = true, textured = textured }
	local f = CreateFrame("Frame", nil, m.frame)
	f:SetFrameLevel(level)
	f:SetAlpha(0)
	f.cb = cb
	cb.frame = f
	cb.bar = CreateFrame("StatusBar", nil, f)
	cb.bar:SetFrameLevel(level + 1)
	cb.bar:SetMinMaxValues(0, 1)
	cb.bar:SetValue(0)
	local over = CreateFrame("Frame", nil, f)
	over:SetFrameLevel(level + 2)
	over:SetAllPoints(f)
	if textured then
		cb.back = f:CreateTexture(nil, "BACKGROUND", nil, 2)
		ns.AtlasPiece(cb.back, textured .. "_bg")
		cb.border = over:CreateTexture(nil, "ARTWORK")
		ns.AtlasPiece(cb.border, textured .. "_fr")
		cb.border:SetAllPoints(f)
		cb.text = ns.NewFont(over, 14)
		cb.time = ns.NewFont(over, 12)
		cb.time:SetJustifyH("RIGHT")
	else
		cb.back = f:CreateTexture(nil, "BACKGROUND")
		cb.back:SetColorTexture(0, 0, 0, 0.6)
		cb.back:SetAllPoints(f)
		cb.bar:SetAllPoints(f)
		cb.bar:SetStatusBarTexture(ns.BAR)
		cb.text = ns.NewFont(over, 11)
		ns.SetPoint(cb.text, "CENTER", f, "CENTER", 0, 0)
	end
	SetCastLook(cb, "cast")
	local function Event(event, u)
		OnCast(cb, event, u)
	end
	for _, e in ipairs(CAST_EVENTS) do
		ns.OnUnit(e, unit, Event)
	end
	return cb
end

-- over the rect r (textured: the fill inside the frame, the spell name
-- under it, the time on its right; flat: the name over the fill)
function ns.LayoutCastBar(cb, m, r)
	local k = ns.k
	ns.PlaceRect(cb.frame, m, r)
	if cb.textured then
		local w = r[3]
		ns.ClearAllPoints(cb.back)
		ns.SetPoint(cb.back, "BOTTOMLEFT", cb.frame, "BOTTOMLEFT", 2 * k, 2 * k)
		cb.back:SetSize((w - 4) * k, 26 * k)
		ns.ClearAllPoints(cb.bar)
		ns.SetPoint(cb.bar, "BOTTOMLEFT", cb.frame, "BOTTOMLEFT", 4 * k, 4 * k)
		cb.bar:SetSize((w - 8) * k, 22 * k)
		ns.ClearAllPoints(cb.text)
		ns.SetPoint(cb.text, "TOP", cb.frame, "BOTTOM", 0, -k)
		cb.text:SetWidth(w * k)
		ns.ClearAllPoints(cb.time)
		ns.SetPoint(cb.time, "RIGHT", cb.frame, "RIGHT", -12 * k, 0)
	else
		cb.text:SetWidth(r[3] * k)
	end
	cb.frame:SetShown(cb.enabled)
	ns.CastBarRefresh(cb)
end
