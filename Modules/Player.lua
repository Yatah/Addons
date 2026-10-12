--[[
	WC3 Console - player panel, as Dota's hero block: the portrait (model in
	its window, the stats column over its right side, the level in a ring
	that fills with the xp), health and mana under the action bars, the
	cast bar above them, the watched reputation on Blizzard's bar standing
	up in its panel left of the chat, the threat over the portrait, the buffs / debuffs, class resources and
	cooldown manager of Blizzard placed around it.
]]

local _, ns = ...
local floor, ceil, max, min, format = math.floor, math.ceil, math.max, math.min, string.format
local Num = ns.Num
local R = ns.R

local LEVEL_COLOR = { 1, 0.7, 0.25 } -- (the level in its ring: Dota's orange gold)
local HIT_PX = 90 -- damage / heal numbers on the portrait

local function Line(left, right, r, g, b)
	GameTooltip:AddDoubleLine(left, right, 1, 0.82, 0, r or 1, g or 1, b or 1)
end

local function Percent(v)
	return format("%.1f%%", v)
end

------------------------------------------------------------------------
-- Stats over the portrait, as Dota's hero portrait: a column on its right
-- side on a shade (no frame of its own): the damage of the weapon that
-- does the most dps, armour, the power of the class (spell: its best
-- school; ranged or melee attack power), its crit, movement speed,
-- avoidance (dodge + parry + block). The model is moved left to keep the
-- face clear. A value that comes secret (in combat) keeps its last text.
-- Details on mouse over; the clicks go through to the portrait.
------------------------------------------------------------------------

local BASE_SPEED = _G.BASE_MOVEMENT_SPEED or 7
-- (art px) column width, line height, icon size, room left at the top
-- (rest / combat icon), width of the shade, shift of the model, font
local STAT_W, STAT_LINE, STAT_ICON, STAT_TOP, STAT_SHADE, MODEL_SHIFT, STAT_FONT = 92, 23, 20, 32, 120, 34, 17
local CASTERS = { MAGE = true, WARLOCK = true, PRIEST = true }
local HYBRIDS = { DRUID = true, SHAMAN = true, PALADIN = true }

-- spell schools (2 holy, 3 fire, 4 nature, 5 frost, 6 shadow, 7 arcane) and
-- healing: their icon, their name; the school of each caster class
local SCHOOL_ICONS = {
	[2] = [[Interface\Icons\Spell_Holy_HolyBolt]], [3] = [[Interface\Icons\Spell_Fire_FlameBolt]],
	[4] = [[Interface\Icons\Spell_Nature_Lightning]], [5] = [[Interface\Icons\Spell_Frost_FrostBolt02]],
	[6] = [[Interface\Icons\Spell_Shadow_ShadowBolt]], [7] = [[Interface\Icons\Spell_Nature_StarFall]],
	heal = [[Interface\Icons\Spell_Holy_FlashHeal]],
}
local SCHOOL_NAMES = { [2] = "Holy", [3] = "Fire", [4] = "Nature", [5] = "Frost", [6] = "Shadow", [7] = "Arcane" }
local CLASS_SCHOOL = { MAGE = 3, WARLOCK = 6, PRIEST = 2, DRUID = 7, SHAMAN = 4, PALADIN = 2 }

-- Spell power: the total bonus of the best school (the gear's "+spell
-- damage" counts in every school, "+shadow damage" in its own only: summing
-- the schools would count the first ones six times), healing too. Returns
-- it and its school (nil when several schools share it).
local function BestSpell()
	local best, school, tie
	local function Try(v, s)
		if not Num(v) then
			return
		end
		if not best or v > best then
			best, school, tie = v, s, false
		elseif v == best then
			tie = true
		end
	end
	if GetSpellBonusDamage then
		for s = 2, 7 do
			Try(GetSpellBonusDamage(s), s)
		end
	end
	if GetSpellBonusHealing then
		Try(GetSpellBonusHealing(), "heal")
	end
	return best, (not tie) and school or nil
end

local function AttackPower(ranged)
	local fn = ranged and UnitRangedAttackPower or UnitAttackPower
	if fn then
		local base, pos, neg = fn("player")
		if Num(base) and Num(pos) and Num(neg) then
			return base + pos + neg
		end
	end
end

-- the power of the class: "spell", "ranged" or "melee" (hybrids: the higher)
local function PowerKind()
	local _, class = UnitClass("player")
	if class == "HUNTER" then
		return "ranged"
	elseif CASTERS[class] or (HYBRIDS[class] and ((BestSpell()) or 0) > (AttackPower() or 0)) then
		return "spell"
	end
	return "melee"
end

local function CritChance(kind)
	if kind == "spell" then
		local best
		if GetSpellCritChance then
			for school = 2, 7 do
				local v = GetSpellCritChance(school)
				if Num(v) and (not best or v > best) then
					best = v
				end
			end
		end
		return best
	elseif kind == "ranged" then
		return GetRangedCritChance and GetRangedCritChance()
	end
	return GetCritChance and GetCritChance()
end

-- melee: main hand (+ off hand when dual wielding); its dps, its range
local function MeleeDamage()
	local low, high, offLow, offHigh = UnitDamage("player")
	local speed, offSpeed = UnitAttackSpeed("player")
	if not (Num(low) and Num(high) and Num(speed) and speed > 0) then
		return nil
	end
	local dps = (low + high) / 2 / speed
	if Num(offLow) and Num(offHigh) and Num(offSpeed) and offSpeed > 0 and offHigh > 0 then
		dps = dps + (offLow + offHigh) / 2 / offSpeed
	end
	return dps, low, high
end

-- ranged weapon (bow, gun, wand...) when one is equipped
local function RangedDamage()
	if not (UnitRangedDamage and GetInventoryItemTexture("player", 18)) then
		return nil
	end
	local speed, low, high = UnitRangedDamage("player")
	if Num(speed) and speed > 0 and Num(low) and Num(high) and high > 0 then
		return (low + high) / 2 / speed, low, high
	end
end

-- Tooltips (values that are secret in combat are left out)
local function WeaponLine(label, low, high, speed)
	if not (Num(low) and Num(high)) then
		return
	end
	local text = format("%d - %d", floor(low), ceil(high))
	if Num(speed) and speed > 0 then
		text = text .. format("  (%.2f s, %.1f %s)", speed, (low + high) / 2 / speed, STAT_DPS_SHORT or "DPS")
	end
	Line(label, text)
end

local function WeaponTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:AddLine(DAMAGE or "Damage", 1, 1, 1)
	local low, high, offLow, offHigh = UnitDamage("player")
	local speed, offSpeed = UnitAttackSpeed("player")
	WeaponLine(INVTYPE_WEAPONMAINHAND or "Main Hand", low, high, speed)
	if GetInventoryItemTexture("player", 17) and Num(offLow) and offLow > 0 then
		WeaponLine(INVTYPE_WEAPONOFFHAND or "Off Hand", offLow, offHigh, offSpeed)
	end
	if GetInventoryItemTexture("player", 18) and UnitRangedDamage then
		local rSpeed, rLow, rHigh = UnitRangedDamage("player")
		WeaponLine(INVTYPE_RANGED or "Ranged", rLow, rHigh, rSpeed)
	end
	local ap = AttackPower()
	if ap then
		Line(STAT_ATTACK_POWER or "Attack Power", tostring(floor(ap)))
	end
	local crit = GetCritChance and GetCritChance()
	if Num(crit) then
		Line(CRIT_CHANCE or "Crit Chance", format("%.2f%%", crit))
	end
	local spell = 0
	for school = 2, 7 do
		local v = GetSpellBonusDamage and GetSpellBonusDamage(school)
		if Num(v) and v > spell then
			spell = v
		end
	end
	if spell > 0 then
		Line(STAT_SPELLDAMAGE or "Spell Damage", tostring(floor(spell)))
	end
	GameTooltip:Show()
end

local function ArmorTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:AddLine(ARMOR or "Armor", 1, 1, 1)
	local _, effective = UnitArmor("player")
	if Num(effective) then
		Line(ARMOR or "Armor", tostring(floor(effective)))
		local level = UnitLevel("player") or 60
		local reduction
		if C_PaperDollInfo and C_PaperDollInfo.GetArmorEffectiveness then
			local ok, r = pcall(C_PaperDollInfo.GetArmorEffectiveness, effective, level)
			if ok and Num(r) then
				reduction = r
			end
		end
		reduction = reduction or effective / (effective + 400 + 85 * min(level, 60))
		Line(DAMAGE_REDUCTION or "Damage reduction", Percent(reduction * 100))
	end
	for _, s in ipairs({ { GetDodgeChance, DODGE_CHANCE or "Dodge" }, { GetParryChance, PARRY_CHANCE or "Parry" }, { GetBlockChance, BLOCK_CHANCE or "Block" } }) do
		local v = s[1] and s[1]()
		if Num(v) and v > 0 then
			Line(s[2], format("%.2f%%", v))
		end
	end
	if UnitResistance then
		local names = { [2] = "Fire", [3] = "Nature", [4] = "Frost", [5] = "Shadow", [6] = "Arcane" }
		for i = 2, 6 do
			local _, total = UnitResistance("player", i)
			if Num(total) and total > 0 then
				Line(_G["RESISTANCE" .. i .. "_NAME"] or names[i], tostring(total))
			end
		end
	end
	GameTooltip:Show()
end

-- the power line: spell power by school (+ healing), or the attack power
-- (base, buffs) and what it adds to the weapon (14 = 1 dps)
local function PowerTooltip(self)
	local kind = PowerKind()
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	if kind == "spell" then
		GameTooltip:AddLine(_G.STAT_SPELLPOWER or "Spell Power", 1, 1, 1)
		for s = 2, 7 do
			local v = GetSpellBonusDamage and GetSpellBonusDamage(s)
			if Num(v) then
				Line(_G["DAMAGE_SCHOOL" .. s] or SCHOOL_NAMES[s], "+" .. floor(v))
			end
		end
		local heal = GetSpellBonusHealing and GetSpellBonusHealing()
		if Num(heal) then
			Line(_G.STAT_SPELLHEALING or "Healing", "+" .. floor(heal))
		end
		GameTooltip:AddLine("Bonus of your gear to your spells. The line shows your best school.", 0.7, 0.7, 0.7, true)
	else
		local ranged = kind == "ranged"
		local fn = ranged and UnitRangedAttackPower or UnitAttackPower
		GameTooltip:AddLine(ranged and (_G.RANGED_ATTACK_POWER or "Ranged Attack Power") or (_G.STAT_ATTACK_POWER or "Attack Power"), 1, 1, 1)
		local base, pos, neg
		if fn then
			base, pos, neg = fn("player")
		end
		if Num(base) and Num(pos) and Num(neg) then
			Line("Base", tostring(floor(base)))
			if pos > 0 then
				Line("Buffs", "+" .. floor(pos), 0.25, 1, 0.25)
			end
			if neg < 0 then
				Line("Debuffs", tostring(floor(neg)), 1, 0.25, 0.25)
			end
			GameTooltip:AddLine(format("+%.1f damage per second to your weapon", (base + pos + neg) / 14), 0.7, 0.7, 0.7)
		end
	end
	GameTooltip:Show()
end

-- every crit chance (the line shows the one of the class)
local function CritTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:AddLine(_G.CRIT_CHANCE or "Crit Chance", 1, 1, 1)
	for _, e in ipairs({ { "Melee", "melee" }, { "Ranged", "ranged" }, { "Spell", "spell" } }) do
		local ok, v = pcall(CritChance, e[2])
		if ok and Num(v) then
			Line(e[1], Percent(v))
		end
	end
	GameTooltip:Show()
end

local function SpeedTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:AddLine(_G.STAT_MOVEMENT_SPEED or "Movement speed", 1, 1, 1)
	local cur, run, _, swim = GetUnitSpeed("player")
	for _, e in ipairs({ { "Now", cur }, { "Run", run }, { "Swim", swim } }) do
		if Num(e[2]) then
			Line(e[1], format("%d%%", floor(e[2] / BASE_SPEED * 100 + 0.5)))
		end
	end
	GameTooltip:Show()
end

local function Safe(fn)
	return function(self)
		if not pcall(fn, self) then
			GameTooltip:Show()
		end
	end
end

-- the lines: key, icon, tooltip, value(kind) -> text (nil: not readable
-- now) [, icon]
local STAT_LINES = {
	-- (the damage of the weapon that does the most dps: melee or ranged)
	{ key = "damage", icon = [[Interface\Icons\INV_Sword_04]], tip = WeaponTooltip, value = function()
		local mDps, mLow, mHigh = MeleeDamage()
		local rDps, rLow, rHigh = RangedDamage()
		local slot, low, high = 16, mLow, mHigh
		if rDps and (not mDps or rDps > mDps) then
			slot, low, high = 18, rLow, rHigh
		end
		if low and high then
			local icon = GetInventoryItemTexture("player", slot) or (slot == 18 and [[Interface\Icons\INV_Weapon_Bow_07]]) or [[Interface\Icons\INV_Sword_04]]
			return format("%d-%d", floor(low), ceil(high)), icon
		end
	end },
	{ key = "armor", icon = [[Interface\Icons\INV_Chest_Chain_05]], tip = ArmorTooltip, value = function()
		local _, effective = UnitArmor("player")
		if Num(effective) then
			return tostring(floor(effective))
		end
	end },
	-- (spell: the icon of its best school, the class's school when no school
	-- leads)
	{ key = "power", tip = PowerTooltip, value = function(kind)
		if kind == "spell" then
			local v, school = BestSpell()
			if Num(v) then
				local _, class = UnitClass("player")
				return tostring(floor(v)), SCHOOL_ICONS[school or CLASS_SCHOOL[class] or 3]
			end
		else
			local v = AttackPower(kind == "ranged")
			if Num(v) then
				return tostring(floor(v)), kind == "ranged" and [[Interface\Icons\Ability_TrueShot]] or [[Interface\Icons\Ability_Warrior_BattleShout]]
			end
		end
	end },
	{ key = "crit", icon = [[Interface\Icons\Ability_CriticalStrike]], tip = CritTooltip, value = function(kind)
		local v = CritChance(kind)
		if Num(v) then
			return Percent(v)
		end
	end },
	{ key = "speed", icon = [[Interface\Icons\Ability_Rogue_Sprint]], tip = SpeedTooltip, value = function()
		local cur, run = GetUnitSpeed("player")
		local v = (Num(cur) and cur > 0) and cur or run
		if Num(v) then
			local p = floor(v / BASE_SPEED * 100 + 0.5)
			local color = (p > 100 and "|cff40ff40") or (p < 100 and "|cffff5050") or ""
			return format("%s%d%%", color, p)
		end
	end },
	{ key = "defense", icon = [[Interface\Icons\Ability_Defend]], tip = ArmorTooltip, value = function()
		local total, any = 0, false
		for _, name in ipairs({ "GetDodgeChance", "GetParryChance", "GetBlockChance" }) do
			local fn = _G[name]
			local v = fn and fn()
			if Num(v) then
				total, any = total + v, true
			end
		end
		if any then
			return Percent(total)
		end
	end },
}

local function UpdateStats(st, speedOnly)
	local kind = speedOnly and st.kind or PowerKind()
	st.kind = kind
	for _, def in ipairs(STAT_LINES) do
		if not speedOnly or def.key == "speed" then
			local ok, text, icon = pcall(def.value, kind)
			if ok and text then
				local line = st.lines[def.key]
				line.text:SetText(text)
				if icon and icon ~= line.iconFile then
					line.iconFile = icon
					line.icon:SetTexture(icon)
				end
			end
		end
	end
end

local function NewStats(m)
	local f = m.frame
	local st = { lines = {} }
	-- the shade: over the model, under the frame of its window
	st.shade = CreateFrame("Frame", nil, f)
	st.shade:EnableMouse(false)
	local t = st.shade:CreateTexture(nil, "ARTWORK")
	t:SetAllPoints(st.shade)
	t:SetTexture([[Interface\Buttons\WHITE8X8]])
	t:SetVertexColor(1, 1, 1, 1)
	if not pcall(t.SetGradient, t, "HORIZONTAL", CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 0.75)) then
		t:SetVertexColor(0, 0, 0, 0.45)
	end
	st.frame = CreateFrame("Frame", nil, f)
	st.frame:EnableMouse(false)
	for _, def in ipairs(STAT_LINES) do
		local line = CreateFrame("Frame", nil, st.frame)
		line.icon = line:CreateTexture(nil, "ARTWORK")
		line.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		line.icon:SetTexture(def.icon)
		line.text = ns.NewFont(line, STAT_FONT)
		line.text:SetJustifyH("RIGHT")
		-- (mouse over only: the clicks reach the portrait under it)
		if line.SetMouseClickEnabled then
			line:SetMouseMotionEnabled(true)
			line:SetMouseClickEnabled(false)
		else
			line:EnableMouse(true)
		end
		line:SetScript("OnEnter", Safe(def.tip))
		line:SetScript("OnLeave", GameTooltip_Hide)
		st.lines[def.key] = line
	end
	-- the stats when they change (gathered), the speed 5 times a second
	st.frame:SetScript("OnEvent", function()
		st.dirty = true
	end)
	for _, e in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "PLAYER_REGEN_ENABLED",
		"UPDATE_SHAPESHIFT_FORM", "SKILL_LINES_CHANGED", "SPELL_POWER_CHANGED", "COMBAT_RATING_UPDATE" }) do
		pcall(st.frame.RegisterEvent, st.frame, e)
	end
	for _, e in ipairs({ "UNIT_STATS", "UNIT_ATTACK_POWER", "UNIT_RANGED_ATTACK_POWER", "UNIT_DAMAGE", "UNIT_RANGEDDAMAGE",
		"UNIT_ATTACK_SPEED", "UNIT_RESISTANCES", "UNIT_AURA", "UNIT_INVENTORY_CHANGED" }) do
		pcall(st.frame.RegisterUnitEvent, st.frame, e, "player")
	end
	local elapsed = 0
	st.frame:SetScript("OnUpdate", function(_, e)
		elapsed = elapsed + e
		if elapsed >= 0.2 then
			elapsed = 0
			local all = st.dirty
			st.dirty = nil
			UpdateStats(st, not all)
		end
	end)
	m.stats = st
end

local function LayoutStats(m)
	local st, k, mo = m.stats, ns.k, R.p_model
	local base = m.frame:GetFrameLevel()
	-- the shade over the model (+1), under the window frame (+7); the lines
	-- over the portrait button (+12)
	st.shade:SetFrameLevel(base + 2)
	st.frame:SetFrameLevel(base + 13)
	ns.PlaceRect(st.shade, m, { mo[1] + mo[3] - STAT_SHADE, mo[2], STAT_SHADE, mo[4] })
	-- (as Dota: the icons against the right edge of the window, the values
	-- right aligned before them)
	local right, top = mo[1] + mo[3] - 2, mo[2] + mo[4] - STAT_TOP
	for i, def in ipairs(STAT_LINES) do
		local line = st.lines[def.key]
		line:SetFrameLevel(base + 13)
		ns.PlaceRect(line, m, { right - STAT_W, top - i * STAT_LINE, STAT_W, STAT_LINE })
		line.icon:SetSize(STAT_ICON * k, STAT_ICON * k)
		ns.ClearAllPoints(line.icon)
		ns.SetPoint(line.icon, "RIGHT", line, "RIGHT", 0, 0)
		ns.ClearAllPoints(line.text)
		ns.SetPoint(line.text, "LEFT", line, "LEFT", 0, 0)
		ns.SetPoint(line.text, "RIGHT", line.icon, "LEFT", -4 * k, 0)
	end
	st.kind = nil
	UpdateStats(st)
end

------------------------------------------------------------------------
-- The model (its view moved left: the face clear of the stats column; the
-- view is reset with the unit)
------------------------------------------------------------------------

local function RefreshModel(m)
	local model = m.model
	if not model:IsVisible() or not UnitExists("player") then
		return
	end
	model:SetUnit("player")
	model:SetPortraitZoom(1)
	model:SetCamDistanceScale(1)
	pcall(model.SetViewTranslation, model, -MODEL_SHIFT * ns.k, 0)
end

------------------------------------------------------------------------
-- Level and XP: the level in its ring, the gold ring filling as Dota's
-- (p_level, 72 px around it): dark bronze where it is empty; from the top,
-- clockwise, the gold ring with its warm glow over the xp, a blue glow
-- over the rested xp beyond it; all gold at the maximum level. The arcs
-- are paused Cooldown swipes of the ring (blocks\xpring) and of its glow
-- (blocks\xpglow).
------------------------------------------------------------------------

local TRACK_COLOR = { 0.30, 0.24, 0.16, 1 }
local XP_GLOW = { 1, 0.55, 0.12, 0.7 }
local RESTED_GLOW = { 0.3, 0.55, 1, 0.6 }
local ARC_SPAN = 100 -- (seconds of the paused cooldown that draws an arc)

-- `frac` of the ring, from 12 o'clock clockwise (reversed swipe, paused)
local function SetArc(cd, frac)
	if frac <= 0.001 then
		cd:Hide()
		return
	end
	cd:Show()
	if cd.Resume then
		cd:Resume()
	end
	cd:SetCooldown(GetTime() - min(frac, 0.999) * ARC_SPAN, ARC_SPAN)
	if cd.Pause then
		cd:Pause()
	end
end

local function NewArc(parent, texture, color)
	local cd = CreateFrame("Cooldown", nil, parent)
	cd:SetAllPoints(parent)
	cd:SetReverse(true)
	cd:SetDrawEdge(false)
	cd:SetDrawBling(false)
	cd:SetHideCountdownNumbers(true)
	cd:SetSwipeTexture(texture)
	cd:SetSwipeColor(color[1], color[2], color[3], color[4])
	return cd
end

-- a frame over the whole ring holding a texture
local function RingLayer(parent, texture, color, sub)
	local l = CreateFrame("Frame", nil, parent)
	l:SetAllPoints(parent)
	l:EnableMouse(false)
	local t = l:CreateTexture(nil, "ARTWORK", nil, sub or 0)
	t:SetAllPoints(parent)
	t:SetTexture(texture)
	t:SetVertexColor(color[1], color[2], color[3], color[4])
	return l, t
end

local function UpdateXP(m)
	local f = m.xpRing
	local cur, maxXP = UnitXP("player"), UnitXPMax("player")
	local capped = (UnitLevel("player") or 0) >= ns.MaxLevel()
	if capped or not (Num(cur) and Num(maxXP) and maxXP > 0) then
		f.full:SetShown(capped)
		f.xp:Hide()
		f.glow:Hide()
		f.rested:Hide()
		return
	end
	f.full:Hide()
	local rested = GetXPExhaustion() or 0
	SetArc(f.xp, cur / maxXP)
	SetArc(f.glow, cur / maxXP)
	SetArc(f.rested, rested > 0 and min(1, (cur + rested) / maxXP) or 0)
end

local function XPTooltip(self)
	local cur, maxXP = UnitXP("player"), UnitXPMax("player")
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:AddLine(format("%s %d %s", LEVEL or "Level", UnitLevel("player") or 0, UnitClass("player") or ""), 1, 1, 1)
	if Num(cur) and Num(maxXP) and maxXP > 0 then
		Line(XP or "Experience", format("%d / %d (%.1f%%)", cur, maxXP, cur / maxXP * 100))
		Line(TUTORIAL_TITLE26 or "Rested", tostring(GetXPExhaustion() or 0))
	end
	GameTooltip:Show()
end

local function NewLevel(m)
	local f = m.frame
	local ring, glow = ns.Art("xpring"), ns.Art("xpglow")
	local x = CreateFrame("Frame", nil, f)
	x:EnableMouse(false)
	-- (bottom to top) rested glow, dark ring, xp glow, gold ring; all gold
	-- at the maximum level
	x.rested = NewArc(x, glow, RESTED_GLOW)
	x.track = RingLayer(x, ring, TRACK_COLOR)
	x.glow = NewArc(x, glow, XP_GLOW)
	x.xp = NewArc(x, ring, { 1, 1, 1, 1 })
	x.full = RingLayer(x, glow, XP_GLOW, 0)
	local gold = x.full:CreateTexture(nil, "ARTWORK", nil, 1)
	gold:SetAllPoints(x)
	gold:SetTexture(ring)
	for _, e in ipairs({ "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION", "PLAYER_ENTERING_WORLD" }) do
		x:RegisterEvent(e)
	end
	x:SetScript("OnEvent", function()
		UpdateXP(m)
	end)
	m.xpRing = x
	-- the level over it
	local b = CreateFrame("Frame", nil, f)
	b:EnableMouse(false)
	b.text = ns.NewFont(b, 20)
	b.text:SetAllPoints(b)
	b.text:SetTextColor(LEVEL_COLOR[1], LEVEL_COLOR[2], LEVEL_COLOR[3])
	b:RegisterEvent("PLAYER_LEVEL_UP")
	b:RegisterEvent("PLAYER_ENTERING_WORLD")
	b:SetScript("OnEvent", function(self, _, level)
		self.text:SetText(tonumber(level) or UnitLevel("player") or "")
	end)
	m.badge = b
	-- the xp tooltip over the ring
	m.xpHover = CreateFrame("Frame", nil, f)
	m.xpHover:EnableMouse(true)
	m.xpHover:SetScript("OnEnter", XPTooltip)
	m.xpHover:SetScript("OnLeave", GameTooltip_Hide)
end

local function LayoutLevel(m)
	local x, base = m.xpRing, m.frame:GetFrameLevel()
	-- over the art (p_over, the dark disc: +7), under the level (+12)
	x:SetFrameLevel(base + 8)
	x.rested:SetFrameLevel(base + 8)
	x.track:SetFrameLevel(base + 9)
	x.glow:SetFrameLevel(base + 10)
	x.xp:SetFrameLevel(base + 11)
	x.full:SetFrameLevel(base + 11)
	ns.PlaceRect(x, m, R.p_level)
	UpdateXP(m)
	m.badge:SetFrameLevel(base + 12)
	ns.PlaceRect(m.badge, m, R.p_badge)
	m.badge.text:SetText(UnitLevel("player") or "")
	m.xpHover:SetFrameLevel(base + 13)
	ns.PlaceRect(m.xpHover, m, R.p_level)
end

------------------------------------------------------------------------
-- Reputation: the watched faction (Reputation panel: "Show as experience
-- bar") on Blizzard's reputation bar standing up, in its own thin panel
-- left of the chat: the panel and the trough in the art, its frame a piece
-- over the fill (rep_fr, as the mana bar's); the fill (p_rep) rising from
-- the bottom, Blizzard's fill of the standing (red .. green), cut in its
-- 20 segments. The fill hidden while no faction is watched (the empty
-- trough stays); faction, standing and progress on mouse over.
------------------------------------------------------------------------

-- Blizzard's fills by standing (1 hated .. 8 exalted: ReputationBarOverrides)
local REP_FILLS = { "Red", "Red", "Orange", "Yellow", "Green", "Green", "Green", "Green" }
local REP_SEGMENTS = 20 -- (STATUS_BAR_NUM_SEGMENTS of Forever)
local REP_DIVIDER = "ui-hud-experiencebar-divider" -- (3 x 10: a stroke across the bar)
local QUARTER = math.pi / 2

local function StandingColor(standing)
	local c = FACTION_BAR_COLORS and FACTION_BAR_COLORS[standing or 4]
	if c then
		return c.r, c.g, c.b
	end
	return 0, 0.6, 0.1
end

-- the fill of the standing: Blizzard's (turned up with the bar), else the
-- bar texture of the HUD in the colour of the standing
local function SetRepFill(bar, standing)
	local atlas = "UI-HUD-ExperienceBar-Fill-Reputation-Faction-" .. (REP_FILLS[standing or 4] or "Green")
	if bar.wc3cFill == atlas then
		return
	end
	bar.wc3cFill = atlas
	if ns.HasAtlas(atlas) and pcall(bar.SetStatusBarTexture, bar, atlas) then
		bar:SetStatusBarColor(1, 1, 1, 1)
	else
		bar:SetStatusBarTexture(ns.BAR)
		bar:SetStatusBarColor(StandingColor(standing))
	end
	local fill = bar:GetStatusBarTexture()
	if fill then
		fill:SetDrawLayer("ARTWORK", 0)
	end
end

local RepTooltip = Safe(function(self)
	local name, standing, low, high, value = ns.WatchedFaction()
	if not name then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:AddLine(name, 1, 1, 1)
	local progress = ""
	if Num(low) and Num(high) and Num(value) then
		local cur, total = value - low, high - low
		progress = total > 0 and format("%d / %d (%.1f%%)", cur, total, cur / total * 100) or "100%"
	end
	local r, g, b = StandingColor(standing)
	GameTooltip:AddDoubleLine(_G["FACTION_STANDING_LABEL" .. (standing or 4)] or "", progress, r, g, b, 1, 1, 1)
	GameTooltip:Show()
end)

local function UpdateRep(m)
	local f = m.rep
	local name, standing, low, high, value = ns.WatchedFaction()
	if not name then
		f.bar:Hide()
		if GameTooltip:IsOwned(f) then
			GameTooltip:Hide()
		end
		return
	end
	-- (bounds that cannot be read: the last fill is kept; at the top of
	-- the last standing, full)
	if Num(low) and Num(high) and Num(value) then
		f.bar:SetValue(high > low and min(1, max(0, (value - low) / (high - low))) or 1)
	end
	SetRepFill(f.bar, standing)
	f.bar:Show()
	if GameTooltip:IsOwned(f) then
		RepTooltip(f)
	end
end

-- Blizzard's segment strokes across the bar, between its 20 segments (its
-- divider stands across a horizontal bar: an upright rect, turned a
-- quarter with its rect, lies across ours)
local function PlaceDividers(bar)
	local w, h = bar:GetWidth(), bar:GetHeight()
	if not (w and h and w > 0 and h > 0) then
		return
	end
	local thick = w * 3 / 10
	for i, t in ipairs(bar.dividers) do
		t:ClearAllPoints()
		t:SetPoint("CENTER", bar, "BOTTOM", 0, h * i / REP_SEGMENTS)
		if t.wc3cTurned then
			t:SetSize(thick, w)
			t:SetRotation(QUARTER)
		else
			t:SetSize(w, max(1, thick / 3))
		end
	end
end

local function NewRep(m)
	-- (its frame, always there: the mouse over it)
	local f = CreateFrame("Frame", nil, m.frame)
	-- (bottom to top) the fill over its dark trough, the frame
	local bar = CreateFrame("StatusBar", nil, f)
	bar:SetOrientation("VERTICAL")
	bar:SetRotatesTexture(true)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	bar:Hide()
	local trough = bar:CreateTexture(nil, "BACKGROUND")
	trough:SetAllPoints(bar)
	trough:SetColorTexture(0.05, 0.04, 0.03, 0.9)
	SetRepFill(bar, 4)
	bar.dividers = {}
	local turned = ns.HasAtlas(REP_DIVIDER)
	for i = 1, REP_SEGMENTS - 1 do
		local t = bar:CreateTexture(nil, "OVERLAY")
		if turned then
			t:SetAtlas(REP_DIVIDER)
			t.wc3cTurned = true
		else
			t:SetColorTexture(0, 0, 0, 0.55)
		end
		bar.dividers[i] = t
	end
	bar:SetScript("OnSizeChanged", PlaceDividers)
	f.bar = bar
	f.over = CreateFrame("Frame", nil, f)
	f.over:EnableMouse(false)
	f.over:SetAllPoints(f)
	local border = f.over:CreateTexture(nil, "ARTWORK")
	ns.AtlasPiece(border, "rep_fr")
	border:SetAllPoints(f)
	-- (mouse over only, as the stats: the clicks go through)
	if f.SetMouseClickEnabled then
		f:SetMouseMotionEnabled(true)
		f:SetMouseClickEnabled(false)
	else
		f:EnableMouse(true)
	end
	f:SetScript("OnEnter", RepTooltip)
	f:SetScript("OnLeave", GameTooltip_Hide)
	-- (UPDATE_FACTION: the standing changes, a faction watched or no longer)
	for _, e in ipairs({ "UPDATE_FACTION", "PLAYER_ENTERING_WORLD" }) do
		pcall(f.RegisterEvent, f, e)
	end
	f:SetScript("OnEvent", function()
		UpdateRep(m)
	end)
	m.rep = f
end

local function LayoutRep(m)
	local f, base = m.rep, m.frame:GetFrameLevel()
	local fr = ns.MOBA.front.rep_fr
	-- over the art (p_over: +7), as the level ring
	f:SetFrameLevel(base + 8)
	f.bar:SetFrameLevel(base + 9)
	f.over:SetFrameLevel(base + 10)
	ns.Place(f, m, fr.x, fr.y, fr.w, fr.h)
	ns.PlaceRect(f.bar, m, R.p_rep)
	PlaceDividers(f.bar)
	UpdateRep(m)
end

------------------------------------------------------------------------
-- Threat on the target (retail's numerical threat: NumericThreatBorder
-- over a bar coloured by the threat status), above the portrait; shown in
-- combat when the target has a threat list
------------------------------------------------------------------------

local THREAT_COLORS = { [0] = { 0.69, 0.69, 0.69 }, { 1, 1, 0.47 }, { 1, 0.6, 0 }, { 1, 0, 0 } }

local function ThreatColor(status)
	if GetThreatStatusColor then
		local ok, r, g, b = pcall(GetThreatStatusColor, status)
		if ok and r then
			return r, g, b
		end
	end
	local c = THREAT_COLORS[status] or THREAT_COLORS[0]
	return c[1], c[2], c[3]
end

local function UpdateThreat(f)
	if not UnitExists("target") or UnitIsDeadOrGhost("target") or not UnitDetailedThreatSituation then
		f:Hide()
		return
	end
	local ok, isTanking, status, _, raw = pcall(UnitDetailedThreatSituation, "player", "target")
	if not ok or ns.IsSecret(raw) or ns.IsSecret(status) or ns.IsSecret(isTanking) then
		f:Hide()
		return
	end
	local display = raw
	if isTanking and UnitThreatPercentageOfLead then
		local ok2, lead = pcall(UnitThreatPercentageOfLead, "player", "target")
		if ok2 and Num(lead) and lead > 0 then
			display = lead
		end
	end
	if type(display) ~= "number" or display <= 0 then
		f:Hide()
		return
	end
	f.text:SetFormattedText("%1.0f%%", display)
	f.bg:SetVertexColor(ThreatColor(status or 0))
	f:Show()
end

local function NewThreat(m)
	local f = CreateFrame("Frame", nil, m.frame)
	f:EnableMouse(false)
	f.bg = f:CreateTexture(nil, "BACKGROUND")
	f.bg:SetTexture([[Interface\TargetingFrame\UI-StatusBar]])
	f.border = f:CreateTexture(nil, "ARTWORK")
	f.border:SetTexture([[Interface\TargetingFrame\NumericThreatBorder]])
	f.border:SetTexCoord(0, 0.765625, 0, 0.5625)
	f.border:SetAllPoints(f)
	f.text = ns.NewFont(f, 17)
	ns.SetPoint(f.text, "CENTER", f.bg, "CENTER", 0, 0)
	for _, e in ipairs({ "PLAYER_TARGET_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED" }) do
		f:RegisterEvent(e)
	end
	for _, e in ipairs({ "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE" }) do
		pcall(f.RegisterUnitEvent, f, e, "player", "target")
	end
	f:SetScript("OnEvent", UpdateThreat)
	m.threat = f
end

local function LayoutThreat(m)
	local f, r, k = m.threat, R.p_threat, ns.k
	f:SetFrameLevel(m.frame:GetFrameLevel() + 10)
	ns.PlaceRect(f, m, r)
	-- (retail: a 49 x 18 frame, the bar 37 x 14 at 3 from the top)
	ns.ClearAllPoints(f.bg)
	ns.SetPoint(f.bg, "TOP", f, "TOP", 0, -r[4] * 3 / 18 * k)
	f.bg:SetSize(r[3] * 37 / 49 * k, r[4] * 14 / 18 * k)
	UpdateThreat(f)
end

------------------------------------------------------------------------
-- Blizzard's buffs / debuffs (BuffFrame, DebuffFrame) at their original
-- size, together in p_auras (above the micro menu, over the minimap): each
-- from the corner its icons start from (their own layout: its rows can be
-- wider than p_auras, then they go past its right side), the debuffs past
-- the last row of buffs shown. Moved in Blizzard's edit mode, they are left
-- to it (hudAuras off; the same for the cooldown manager, hudCooldowns)
------------------------------------------------------------------------

-- a frame moved in edit mode (its own drag, or its selection's): fn
local function WatchDrag(frame, fn)
	if type(frame.OnDragStop) == "function" then
		hooksecurefunc(frame, "OnDragStop", fn)
	end
	if frame.Selection and frame.Selection.HookScript then
		frame.Selection:HookScript("OnDragStop", fn)
	end
end

-- frames given to edit mode: the HUD no longer places them
local function GiveToEditMode(m, key, what, frames)
	if not m.db[key] then
		return
	end
	m.db[key] = false
	for _, name in ipairs(frames) do
		if _G[name] then
			ns.Unfollow(_G[name])
		end
	end
	ns.Print(what .. " moved in edit mode: it keeps them now (Options > Player gives them back to the HUD).")
end

local AURA_FRAMES = { "BuffFrame", "DebuffFrame" }
local AURA_GAP = 14 -- UI units past a row of buffs (its time left)

-- the edges of the icons a frame shows (art px: left, right, bottom, top),
-- nil: none
local function Extent(fr)
	local left, right, low, high
	local ui = UIParent:GetEffectiveScale()
	for _, b in ipairs(fr and fr.auraFrames or {}) do
		local ok, shown, l, r, bottom, top, scale = pcall(function()
			return b:IsShown(), b:GetLeft(), b:GetRight(), b:GetBottom(), b:GetTop(), b:GetEffectiveScale()
		end)
		if ok and shown and Num(l) and Num(r) and Num(bottom) and Num(top) then
			local f = scale / ui / ns.k
			l, r, bottom, top = l * f - ns.ox / ns.k, r * f - ns.ox / ns.k, bottom * f - ns.oy / ns.k, top * f - ns.oy / ns.k
			left, right, low, high = min(left or l, l), max(right or r, r), min(low or bottom, bottom), max(high or top, top)
		end
	end
	return left, right, low, high
end

local function PlaceAuraFrame(m, fr, debuffs)
	local r = R.p_auras
	local function Apply()
		if not m.db.hudAuras then
			return
		end
		local c = fr.AuraContainer
		local right = c and c.addIconsToRight and true or false
		local up = c and c.addIconsToTop and true or false
		-- (the original size: as big as on UIParent)
		local parent = fr:GetParent()
		ns.SetScale(fr, parent and UIParent:GetEffectiveScale() / parent:GetEffectiveScale() or 1)
		local point = (up and "BOTTOM" or "TOP") .. (right and "LEFT" or "RIGHT")
		local x, y = right and r[1] or (r[1] + r[3]), up and r[2] or (r[2] + r[4])
		if debuffs then
			local _, _, low, high = Extent(_G.BuffFrame)
			if up and high then
				y = max(y, high + AURA_GAP / ns.k)
			elseif low then
				y = min(y, low - AURA_GAP / ns.k)
			end
		end
		ns.Follow(m, fr, point, x, y)
		-- (rows that grow to the left: kept from the left side of p_auras)
		if not right then
			local left = Extent(fr)
			if left and left < r[1] then
				ns.Follow(m, fr, point, x + r[1] - left, y)
			end
		end
	end
	if fr:IsProtected() and InCombatLockdown() then
		ns.RunOOC("auraframe" .. fr:GetName(), Apply)
	else
		Apply()
	end
end

local function LayoutAuraFrames(m)
	for i, name in ipairs(AURA_FRAMES) do
		local fr = _G[name]
		if fr and m.db.hudAuras then
			PlaceAuraFrame(m, fr, i == 2)
		elseif fr then
			ns.Unfollow(fr)
		end
	end
end

local function WatchAuraFrames(m)
	for i, name in ipairs(AURA_FRAMES) do
		local fr = _G[name]
		if fr then
			ns.HookPosition(fr, function()
				PlaceAuraFrame(m, fr, i == 2)
			end)
			WatchDrag(fr, function()
				GiveToEditMode(m, "hudAuras", "Buffs / debuffs", AURA_FRAMES)
			end)
		end
	end
	-- (Blizzard's grid layout left intact: placed again once its aura /
	-- edit mode updates are done; the debuffs follow the rows of buffs)
	local function Refresh()
		ns.Defer("aura-layout", function()
			LayoutAuraFrames(m)
		end)
	end
	ns.OnUnit("UNIT_AURA", "player", Refresh)
	ns.OnUnit("UNIT_AURA", "vehicle", Refresh)
	ns.On("PLAYER_ENTERING_WORLD", Refresh)
	ns.On("EDIT_MODE_LAYOUTS_UPDATED", Refresh)
	ns.On("PLAYER_REGEN_ENABLED", Refresh)
end

------------------------------------------------------------------------
-- Blizzard's cooldown manager (its viewers, as edit mode sizes them),
-- centred above the cast bar: the essential cooldowns, the utility ones
-- over them, the tracked buffs over those, each on top of the one under it
-- that is shown
------------------------------------------------------------------------

local VIEWERS = { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer", "BuffBarCooldownViewer" }
local VIEWER_GAP = 6 -- UI units between them, and over the cast bar

local function PlaceViewers(m)
	if not m.db.hudCooldowns then
		return
	end
	if InCombatLockdown() then
		for _, name in ipairs(VIEWERS) do
			local v = _G[name]
			if v and v:IsProtected() then
				ns.RunOOC("viewers", function()
					PlaceViewers(m)
				end)
				return
			end
		end
	end
	local c, k = R.p_cast, ns.k
	local x, y = c[1] + c[3] / 2, c[2] + c[4]
	local under
	m.viewersBusy = true
	for _, name in ipairs(VIEWERS) do
		local v = _G[name]
		if v then
			ns.ClearAllPoints(v)
			if under then
				ns.SetPoint(v, "BOTTOM", under, "TOP", 0, VIEWER_GAP)
			else
				local fs = v:GetEffectiveScale() / UIParent:GetEffectiveScale()
				ns.SetPoint(v, "BOTTOM", UIParent, "BOTTOMLEFT", (ns.ox + x * k) / fs, (ns.oy + y * k) / fs + VIEWER_GAP)
			end
			if v:IsShown() then
				under = v
			end
		end
	end
	m.viewersBusy = false
end

-- (the viewers come with Blizzard's cooldown manager, maybe after us;
-- edit mode puts them back with its own anchoring: placed again after it)
local function WatchViewers(m)
	local function Again()
		if not m.viewersBusy then
			ns.Defer("viewers", function()
				PlaceViewers(m)
			end)
		end
	end
	local function Hook()
		local found = false
		for _, name in ipairs(VIEWERS) do
			local v = _G[name]
			if v then
				found = true
				if not v.wc3cViewer then
					v.wc3cViewer = true
					for _, method in ipairs({ "SetPoint", "SetPointBase", "ApplySystemAnchor" }) do
						if type(v[method]) == "function" then
							hooksecurefunc(v, method, Again)
						end
					end
					WatchDrag(v, function()
						GiveToEditMode(m, "hudCooldowns", "Cooldown manager", VIEWERS)
					end)
					v:HookScript("OnShow", Again)
					v:HookScript("OnHide", Again)
				end
			end
		end
		if found then
			Again()
		end
	end
	Hook()
	ns.On("ADDON_LOADED", Hook)
	ns.On("PLAYER_ENTERING_WORLD", Hook)
	ns.On("EDIT_MODE_LAYOUTS_UPDATED", Again)
end

-- /wc3c cdm: where the viewers of the cooldown manager are
function ns.ViewerDebug()
	for _, name in ipairs(VIEWERS) do
		local v = _G[name]
		if not v then
			ns.Print(name .. ": not found")
		else
			local point, rel, relPoint, x, y = v:GetPoint(1)
			local relName = rel and rel.GetName and rel:GetName() or tostring(rel)
			ns.Print(format("%s: %s, %s on %s %s (%.0f, %.0f), %.0f x %.0f", name, v:IsShown() and "shown" or "hidden",
				tostring(point), tostring(relName), tostring(relPoint), x or 0, y or 0, v:GetWidth() or 0, v:GetHeight() or 0))
		end
	end
end

-- class resources (combo points, totems...) over the portrait block
-- (out of combat when the container holds a protected frame, the pet frame)
function ns.PlacePlayerResources(m)
	local c = ns.PlayerResourceContainer and ns.PlayerResourceContainer()
	if not c or c:GetParent() ~= UIParent then
		return
	end
	if c:IsProtected() and InCombatLockdown() then
		ns.RunOOC("resources", function()
			ns.PlacePlayerResources(m)
		end)
		return
	end
	local w, h, k = c:GetWidth() or 0, c:GetHeight() or 0, ns.k
	if w > 1 and h > 1 then
		ns.SetScale(c, min(240 * k / w, 22 * k / h))
	end
	-- (16 px above the top of the centre island, art y 290)
	ns.Follow(m, c, "BOTTOM", 1130, 306)
end

------------------------------------------------------------------------
-- Hit indicator: damage taken / heals received on the portrait, as the
-- Blizzard player frame (its own CombatFeedback code when the client has
-- it: it reads the combat values that are secret for addons)
------------------------------------------------------------------------

local HIT_COLORS = {
	WOUND = { 1, 0.1, 0.1 },
	HEAL = { 0.1, 1, 0.1 },
	ENERGIZE = { 0.41, 0.8, 0.94 },
	BLOCK = { 1, 1, 1 },
}

local function OwnHit(h, action, flags, amount)
	local size = h.fontHeight
	local text
	if action == "WOUND" or action == "HEAL" or action == "ENERGIZE" then
		text = amount
		local ok, crit = pcall(function()
			return flags == "CRITICAL" or flags == "CRUSHING"
		end)
		if ok and crit then
			size = size * 1.5
		end
	else
		text = _G[action] or action
	end
	local c = HIT_COLORS[action] or HIT_COLORS.BLOCK
	h.text:SetFont(ns.FONT, max(8, floor(size + 0.5)), "OUTLINE")
	h.text:SetTextColor(c[1], c[2], c[3])
	if pcall(h.text.SetText, h.text, text) then
		h.start = GetTime()
		h.text:SetAlpha(0)
		h.text:Show()
	end
end

local function OwnHitUpdate(h)
	if not h.start then
		return
	end
	local t = GetTime() - h.start
	if t < 0.2 then
		h.text:SetAlpha(t / 0.2)
	elseif t < 0.8 then
		h.text:SetAlpha(1)
	elseif t < 1.4 then
		h.text:SetAlpha(1 - (t - 0.8) / 0.6)
	else
		h.text:Hide()
		h.start = nil
	end
end

local function NewHits(m)
	local h = CreateFrame("Frame", nil, m.frame)
	h:SetFrameLevel(m.frame:GetFrameLevel() + 3) -- (over the model, under the name)
	h:SetAllPoints(m.model)
	h.text = h:CreateFontString(nil, "OVERLAY", "NumberFontNormalHuge")
	ns.SetPoint(h.text, "CENTER", m.model, "CENTER", 0, 0)
	h.text:Hide()
	local blizzard = _G.CombatFeedback_Initialize and _G.CombatFeedback_OnCombatEvent and _G.CombatFeedback_OnUpdate
	local function Init()
		h.fontHeight = HIT_PX * ns.k
		if blizzard then
			pcall(_G.CombatFeedback_Initialize, h, h.text, h.fontHeight)
		end
	end
	Init()
	ns.On("WC3C_LAYOUT", Init)
	h:SetScript("OnUpdate", function(self, elapsed)
		if blizzard then
			if not pcall(_G.CombatFeedback_OnUpdate, self, elapsed) then
				blizzard = nil
			end
		else
			OwnHitUpdate(self)
		end
	end)
	ns.OnUnit("UNIT_COMBAT", "player", function(_, _, action, flags, amount, school)
		if not m.db.hits then
			return
		end
		if blizzard and pcall(_G.CombatFeedback_OnCombatEvent, h, action, flags, amount, school) then
			return
		end
		blizzard = nil
		OwnHit(h, action, flags, amount)
	end)
end

------------------------------------------------------------------------
-- Module
------------------------------------------------------------------------

local function UpdateHealth(m)
	local ratio = ns.UpdateUnitHealth(m)
	if not ratio then
		return
	end
	if not m.health.wc3cAtlas then
		-- classic texture: green to red with the health
		if ratio < 0.5 then
			m.health:SetStatusBarColor(1, 2 * ratio, 0, 1)
		else
			m.health:SetStatusBarColor(2 * (1 - ratio), 1, 0, 1)
		end
	end
	-- low health: the window pulses red
	local limit = m.db.lowHealth
	local low = limit > 0 and ratio <= limit / 100 and not UnitIsDeadOrGhost("player")
	if low ~= m.lowHP then
		m.lowHP = low
		m.alarm:SetShown(low)
		if low then
			m.alarm.pulse:Play()
		else
			m.alarm.pulse:Stop()
		end
	end
end

local function UpdateStatus(m)
	local combat = UnitAffectingCombat("player")
	m.combatIcon:SetShown(combat and true or false)
	m.restIcon:SetShown((IsResting() and not combat) and true or false)
	m.leaderIcon:SetShown(UnitIsGroupLeader("player") and true or false)
end

ns.RegisterModule({
	key = "player",
	label = "Player",
	order = 20,
	level = 20,
	defaults = { castBar = true, hits = true, percent = false, lowHealth = 25, hudAuras = true, hudCooldowns = true },
	settings = {
		{ type = "toggle", key = "castBar", label = "HUD cast bar" },
		-- (off: where Blizzard's edit mode puts them; moving them there turns it off)
		{ type = "toggle", key = "hudAuras", label = "Buffs / debuffs placed by the HUD" },
		{ type = "toggle", key = "hudCooldowns", label = "Cooldown manager placed by the HUD" },
		{ type = "toggle", key = "hits", label = "Damage / heals on the portrait" },
		{ type = "toggle", key = "percent", label = "Health in percent" },
		{ type = "range", key = "lowHealth", label = "Low health warning (%)", min = 0, max = 50, step = 5 },
	},
	Create = function(m)
		local f = m.frame
		local base = f:GetFrameLevel()
		m.unit = "player"
		-- the window behind the model, pulsing red at low health
		m.window = f:CreateTexture(nil, "BACKGROUND")
		m.window:SetColorTexture(ns.WINDOW[1], ns.WINDOW[2], ns.WINDOW[3], 1)
		m.alarm = f:CreateTexture(nil, "BACKGROUND", nil, 1)
		m.alarm:SetColorTexture(1, 0, 0, 1)
		m.alarm:SetAllPoints(m.window)
		m.alarm:Hide()
		m.alarm.pulse = m.alarm:CreateAnimationGroup()
		m.alarm.pulse:SetLooping("BOUNCE")
		local fade = m.alarm.pulse:CreateAnimation("Alpha")
		fade:SetFromAlpha(0)
		fade:SetToAlpha(1)
		fade:SetDuration(1)
		m.model = CreateFrame("PlayerModel", nil, f)
		m.model:SetFrameLevel(base + 1)
		m.model:SetScript("OnShow", function()
			RefreshModel(m)
		end)
		-- the portrait: target, menu; the bars too
		m.button = ns.UnitButton("WC3C_playerUnitButton", f, "player", base + 12)
		m.click = ns.UnitButton("WC3C_playerMobaClick", f, "player", base + 12)
		m.health = ns.NewBar(f, base + 5, "PLAYER_HEALTH")
		m.power = ns.NewBar(f, base + 6, "MANA")
		local texts = CreateFrame("Frame", nil, f)
		texts:SetFrameLevel(base + 9)
		texts:SetAllPoints(f)
		m.healthText = ns.NewFont(texts, 20)
		m.powerText = ns.NewFont(texts, 14)
		m.name = ns.NewFont(texts, 19)
		m.cast = ns.NewCastBar(m, "player", base + 8, "castP")
		-- status icons
		local icons = CreateFrame("Frame", nil, f)
		icons:SetFrameLevel(base + 14)
		icons:SetAllPoints(f)
		m.combatIcon = icons:CreateTexture(nil, "OVERLAY")
		m.combatIcon:SetTexture([[Interface\CharacterFrame\UI-StateIcon]])
		m.combatIcon:SetTexCoord(0.5, 1, 0, 0.484375)
		m.restIcon = icons:CreateTexture(nil, "OVERLAY")
		m.restIcon:SetTexture([[Interface\CharacterFrame\UI-StateIcon]])
		m.restIcon:SetTexCoord(0, 0.5, 0, 0.421875)
		m.leaderIcon = icons:CreateTexture(nil, "OVERLAY")
		m.leaderIcon:SetTexture([[Interface\GroupFrame\UI-Group-LeaderIcon]])
		NewHits(m)
		NewLevel(m)
		NewRep(m)
		NewStats(m)
		NewThreat(m)
		WatchAuraFrames(m)
		WatchViewers(m)
		ns.WatchName(m)

		local function Health()
			UpdateHealth(m)
		end
		ns.OnUnit("UNIT_HEALTH", "player", Health)
		ns.OnUnit("UNIT_MAXHEALTH", "player", Health)
		for _, e in ipairs({ "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" }) do
			ns.On(e, Health)
		end
		ns.OnPower("player", function()
			ns.UpdateUnitPower(m)
		end)
		local function Model()
			RefreshModel(m)
		end
		ns.OnUnit("UNIT_MODEL_CHANGED", "player", Model)
		ns.OnUnit("UNIT_PORTRAIT_UPDATE", "player", Model)
		for _, e in ipairs({ "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_UPDATE_RESTING", "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED" }) do
			ns.On(e, function()
				UpdateStatus(m)
			end)
		end
		ns.On("PLAYER_ENTERING_WORLD", function()
			Model()
			Health()
			ns.UpdateUnitPower(m)
			UpdateStatus(m)
		end)
	end,
	Layout = function(m)
		local mo, hb, pw = R.p_model, R.p_health, R.p_power
		ns.PlaceRect(m.window, m, mo)
		ns.PlaceRect(m.model, m, mo)
		ns.PlaceRect(m.button, m, mo)
		ns.PlaceRect(m.click, m, { hb[1], pw[2], hb[3], hb[2] + hb[4] - pw[2] })
		ns.PlaceRect(m.health, m, hb)
		ns.PlaceRect(m.power, m, pw)
		ns.TextOnBar(m.healthText, m.health)
		ns.TextOnBar(m.powerText, m.power)
		ns.LayoutName(m, R.p_name, 19)
		m.cast.enabled = m.db.castBar
		ns.LayoutCastBar(m.cast, m, R.p_cast)
		ns.Pieces(m, "front", { "p_over", "p_bars" })
		LayoutLevel(m)
		LayoutRep(m)
		LayoutStats(m)
		LayoutThreat(m)
		local x, y = mo[1] + mo[3] - 18, mo[2] + mo[4] - 18
		ns.Place(m.combatIcon, m, x, y, 26, 26, "CENTER")
		ns.Place(m.restIcon, m, x, y, 26, 26, "CENTER")
		ns.Place(m.leaderIcon, m, mo[1] + 16, mo[2] + mo[4] - 16, 18, 18, "CENTER")
		ns.PlacePlayerResources(m)
		LayoutAuraFrames(m)
		PlaceViewers(m)
		-- Blizzard's pet frame over the portrait when the pet panel is off
		-- (on Forever it lives in the frame of the class resources, placed
		-- above: not moved on its own)
		local pet = _G.PetFrame
		if pet and pet:GetParent() == UIParent and not pet.isManagedFrame and not ns.Enabled("pet") then
			ns.Follow(m, pet, "BOTTOMLEFT", 1140, 330)
		end
		UpdateHealth(m)
		ns.UpdateUnitPower(m)
		UpdateStatus(m)
		RefreshModel(m)
	end,
})
