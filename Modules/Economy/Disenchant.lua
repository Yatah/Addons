--[[
	WC3 Console - economy: can an item be disenchanted, and who can do it
	(Enchant, Craft & DE). Nothing is taken for granted: an item gives
	auctions to a lot only once the game confirmed it can be disenchanted
	and an enchanter of the account can do it.

	State of an item (by item id: a random suffix changes nothing)
	  "ok"       confirmed: its tooltip says so ("Disenchantable",
	             "Disenchanting requires Enchanting (n)": the skill is read
	             there), a disenchant of it was seen, or an exception of
	             this client
	  "no"       forbidden: "Cannot be disenchanted", an exception of this
	             client, or what the game never disenchants (not uncommon,
	             rare or epic gear, shirts, tabards)
	  "unknown"  not known yet: item data loading, no such line in its
	             tooltip (the client may show it to some characters only).
	             Never counted as disenchantable.
	The answers of the game are kept for the account (eco.deItems), for the
	client they were read on (a new build of the client asks again).

	Who: an enchanter of the account on the realm and side of the holder
	(the items go by mail; a soulbound one stays with its holder), its
	Enchanting rank known and high enough, the Disenchant spell not
	missing. A rank not known is no rank.

	Disenchants seen (eco.deSeen, per client): what each disenchant of the
	account gave, per item and per lot. They confirm the item, and they are
	what can validate a yield table on this client (Analysis: until then a
	lot is an estimate, never advised).

	/wc3c eco de <item id or link>: what the console knows of an item.
]]

local _, ns = ...
local Eco = ns.Economy
local format, tonumber, tostring, type, pairs, ipairs = string.format, tonumber, tostring, type, pairs, ipairs
local sort, concat = table.sort, table.concat

local DB, Item, BaseID, LinkID = Eco.DB, Eco.Item, Eco.BaseID, Eco.LinkID

local DISENCHANT, ENCHANTING = 13262, 333
local RULES = 1 -- (another version of these rules: the kept answers are asked again)
local TIPS_PER_PASS = 300 -- tooltips read per computation of the window
local UNKNOWN_AGAIN = 30 -- seconds before a tooltip that said nothing is read again
local SEEN_WITHIN = 5 -- seconds between a disenchant and its loot

-- the client: its version and its build (GetBuildInfo)
local VERSION, BUILD
do
	local v, b = "?", "?"
	if GetBuildInfo then
		local ok, version, build = pcall(GetBuildInfo)
		if ok then
			v, b = tostring(version or "?"), tostring(build or "?")
		end
	end
	VERSION, BUILD = v, b
end
local CLIENT = VERSION .. "." .. BUILD
Eco.CLIENT_VERSION, Eco.CLIENT = VERSION, CLIENT

------------------------------------------------------------------------
-- Exceptions by item id, for the client they were seen on: its version
-- (as GetBuildInfo gives it; any build of it), the build seen, the
-- English name (checked on an English client: another name is told by
-- /wc3c eco de, the exception still applies), why
------------------------------------------------------------------------

local EXCEPTIONS = {
	-- Greater Magic Wand: an uncommon wand (made by enchanters) of a
	-- disenchantable item level, yet its tooltip says "Cannot be
	-- disenchanted" and Disenchant refuses it ("That item is not a valid
	-- target."), seen on Forever 1.60.1.70245 on 2026-10-10, after the
	-- Enchant tab had advised to buy them. Its id: the market's data of that
	-- day (its vendor price of 2 silver, as in its tooltip; 1398 listed at
	-- 1 silver); to check in game: /wc3c eco de 11288.
	[11288] = { state = "no", version = "1.60.1", build = "70245", name = "Greater Magic Wand",
		why = "Cannot be disenchanted (its tooltip and a refused Disenchant, Forever 1.60.1.70245)" },
}
Eco.DE_EXCEPTIONS = EXCEPTIONS

local function Exception(id)
	local x = EXCEPTIONS[id]
	if x and x.version == VERSION then
		return x
	end
end

------------------------------------------------------------------------
-- The disenchant lines of a tooltip, in the language of the client
------------------------------------------------------------------------

-- a line without its colours, trimmed
local function Clean(text)
	return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$"))
end

local function Escape(s)
	return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end

-- a format of the client ("Disenchanting requires %s (%d)", or "%1$s"...)
-- as a pattern, and which of its captures is the number
local function FormatPattern(fmt)
	local parts, pos, n, numberAt = { "^" }, 1, 0, nil
	while true do
		local a, b, spec = fmt:find("%%(%d*%$?[sd])", pos)
		if not a then
			break
		end
		parts[#parts + 1] = Escape(fmt:sub(pos, a - 1))
		n = n + 1
		if spec:sub(-1) == "d" then
			parts[#parts + 1] = "(%d+)"
			numberAt = n
		else
			parts[#parts + 1] = "(.-)"
		end
		pos = b + 1
	end
	parts[#parts + 1] = Escape(fmt:sub(pos)) .. "$"
	return concat(parts), numberAt
end
Eco.DEFormatPattern = FormatPattern

-- the texts of the client (ITEM_DISENCHANT_*); the English ones only when
-- they are missing on an English client
local texts
local function Texts()
	if texts then
		return texts
	end
	local en = ((GetLocale and GetLocale()) or ""):match("^en") ~= nil
	local no = _G.ITEM_DISENCHANT_NOT_DISENCHANTABLE or (en and "Cannot be disenchanted") or nil
	local any = _G.ITEM_DISENCHANT_ANY_SKILL or (en and "Disenchantable") or nil
	local minSkill = _G.ITEM_DISENCHANT_MIN_SKILL or (en and "Disenchanting requires %s (%d)") or nil
	texts = { no = no and Clean(no), any = any and Clean(any) }
	if minSkill then
		texts.min, texts.minAt = FormatPattern(Clean(minSkill))
	end
	texts.source = (_G.ITEM_DISENCHANT_NOT_DISENCHANTABLE and _G.ITEM_DISENCHANT_ANY_SKILL and _G.ITEM_DISENCHANT_MIN_SKILL and "the client's")
		or (en and "English (some missing on this client)") or "missing on this client"
	return texts
end

-- (tests: another language)
function Eco.DEResetTexts()
	texts = nil
end

-- what a tooltip says: "ok" / "no", the skill asked, the line; nil: nothing
local function Verdict(lines, count)
	local t = Texts()
	for i = 1, count do
		local text = lines[i]
		if not ns.IsSecret(text) and type(text) == "string" then
			text = Clean(text)
			if t.no and text == t.no then
				return "no", nil, text
			elseif t.any and text == t.any then
				return "ok", nil, text
			elseif t.min then
				local caps = { text:match(t.min) }
				if caps[1] then
					return "ok", t.minAt and tonumber(caps[t.minAt]), text
				end
			end
		end
	end
end

-- The lines of the tooltip of an item, two ways: the tooltip data of the
-- game (C_TooltipInfo), and a hidden tooltip of our own (the lines a
-- tooltip shows, those added while it is shown included). Each: lines,
-- their count, how they were read (nil: that way is missing)
local function InfoLines(id, link)
	local T = _G.C_TooltipInfo
	if not (T and (T.GetItemByID or T.GetHyperlink)) then
		return nil, 0
	end
	local fn, arg = T.GetItemByID, id
	if (link or not fn) and T.GetHyperlink then
		fn, arg = T.GetHyperlink, link or ("item:" .. id)
	end
	local ok, data = pcall(fn, arg)
	if ok and type(data) == "table" and type(data.lines) == "table" then
		local U, out = _G.TooltipUtil, {}
		for i, line in ipairs(data.lines) do
			if type(line) == "table" then
				if line.leftText == nil and line.args and U and U.SurfaceArgs then
					pcall(U.SurfaceArgs, line)
				end
				out[i] = line.leftText
			end
		end
		return out, #data.lines, "tooltip data"
	end
	return nil, 0
end

local scanTip
local function ScanLines(id, link)
	if not scanTip then
		local ok, tip = pcall(CreateFrame, "GameTooltip", "WC3C_DEScanTip", nil, "GameTooltipTemplate")
		if not (ok and tip) then
			return nil, 0
		end
		scanTip = tip
	end
	local tip = scanTip
	tip:SetOwner(_G.WorldFrame or UIParent, "ANCHOR_NONE")
	tip:ClearLines()
	local out, count = {}, 0
	if pcall(tip.SetHyperlink, tip, link or ("item:" .. id)) then
		count = tip:NumLines() or 0
		for i = 1, count do
			local fs = _G["WC3C_DEScanTipTextLeft" .. i]
			out[i] = fs and fs:GetText()
		end
	end
	tip:Hide()
	return out, count, "hidden tooltip"
end

-- What the tooltip of an item says: the tooltip data first, the hidden
-- tooltip when the data says nothing. State ("ok" / "no" / nil), skill,
-- the line; read: how many lines were read in all (0: none could be)
local function ReadTooltip(id, link)
	local read = 0
	for _, fn in ipairs({ InfoLines, ScanLines }) do
		local lines, count = fn(id, link)
		if lines and count > 0 then
			read = read + count
			local state, skill, line = Verdict(lines, count)
			if state then
				return state, skill, line, read
			end
		end
	end
	return nil, nil, nil, read
end

------------------------------------------------------------------------
-- The state of an item
------------------------------------------------------------------------

local gen = 0 -- (changes with every new answer: the lots cached are computed again)
Eco.deGen = 0
local function Changed()
	gen = gen + 1
	Eco.deGen = gen
end

local unknownAt = {} -- id -> when its tooltip said nothing
local budget = TIPS_PER_PASS
local refreshSoon = false

-- (each computation of the window: Eco.NewPass)
function Eco.DENewPass()
	budget = TIPS_PER_PASS
end

local function RefreshSoon()
	if refreshSoon or not C_Timer then
		return
	end
	refreshSoon = true
	C_Timer.After(0.5, function()
		refreshSoon = false
		if Eco.Refresh then
			Eco.Refresh()
		end
	end)
end

local function Kept()
	local e = DB()
	if type(e.deItems) ~= "table" then
		e.deItems = {}
	end
	return e.deItems
end

local function Keep(id, state, skill, src, line)
	local k = Kept()
	local old = k[id]
	if not (type(old) == "table" and old.v == CLIENT and old.r == RULES and old.s == state and old.k == skill and old.src == src) then
		k[id] = { s = state, k = skill, src = src, l = line, v = CLIENT, r = RULES, t = time() }
		Changed()
	end
	unknownAt[id] = nil
end

-- what the game never disenchants
local NOT_GEAR = { [""] = true, INVTYPE_NON_EQUIP = true, INVTYPE_NON_EQUIP_IGNORE = true, INVTYPE_BAG = true, INVTYPE_QUIVER = true,
	INVTYPE_AMMO = true }
local function Rules(it)
	if it.class ~= 2 and it.class ~= 4 then
		return "not a weapon or an armor"
	elseif not it.quality or it.quality < 2 or it.quality > 4 then
		return "only uncommon, rare and epic items are disenchanted"
	elseif not it.equipLoc or NOT_GEAR[it.equipLoc] then
		return "not equippable"
	elseif it.equipLoc == "INVTYPE_BODY" or it.equipLoc == "INVTYPE_TABARD" then
		return "shirts and tabards are not disenchanted"
	end
end

local function ItemID(ref)
	if type(ref) == "number" then
		return ref
	elseif type(ref) == "string" and ref:find("item:", 1, true) then
		return LinkID(ref)
	end
	return BaseID(ref)
end

local function WhyOf(src, line)
	if src == "seen" then
		return "a disenchant of it was seen on this client"
	elseif line then
		return format("its tooltip says \"%s\"", line)
	end
	return src
end

-- The state of an item (id, price key "id:suffix" or link): "ok", "no",
-- "unknown"; why; the Enchanting its tooltip asks (nil: not said); the
-- source ("exception", "rules", "tooltip", "seen", "loading")
function Eco.DEState(ref)
	local id = ItemID(ref)
	if not id then
		return "unknown", "no item id", nil, "loading"
	end
	local x = Exception(id)
	if x then
		return x.state, x.why, x.skill, "exception"
	end
	local it = Item(id)
	if not it then
		return "unknown", "its data is not loaded yet", nil, "loading"
	end
	local rule = Rules(it)
	if rule then
		return "no", rule, nil, "rules"
	end
	local kept = Kept()[id]
	if type(kept) == "table" and kept.v == CLIENT and kept.r == RULES and (kept.s == "ok" or kept.s == "no") then
		return kept.s, WhyOf(kept.src, kept.l), kept.k, kept.src
	end
	local at = unknownAt[id]
	if at and GetTime() - at < UNKNOWN_AGAIN then
		return "unknown", "its tooltip says nothing about disenchanting (on this character)", nil, "tooltip"
	end
	if budget <= 0 then
		RefreshSoon()
		return "unknown", "not checked yet (next refresh)", nil, "pending"
	end
	budget = budget - 1
	local state, skill, line, read = ReadTooltip(id, type(ref) == "string" and ref:find("item:", 1, true) and ref or nil)
	if state then
		Keep(id, state, skill, "tooltip", line)
		return state, WhyOf("tooltip", line), skill, "tooltip"
	end
	if read > 0 then
		unknownAt[id] = GetTime()
	end
	return "unknown", read > 0 and "its tooltip says nothing about disenchanting (on this character)"
		or "its tooltip could not be read yet", nil, "tooltip"
end

-- What the game answered so far, for this client: confirmed, forbidden
-- (tooltips, disenchants seen), not known (tooltips without a line, this
-- session); the source of the texts
function Eco.DEStats()
	local ok, no, unknown = 0, 0, 0
	for _, k in pairs(Kept()) do
		if type(k) == "table" and k.v == CLIENT and k.r == RULES then
			if k.s == "ok" then
				ok = ok + 1
			elseif k.s == "no" then
				no = no + 1
			end
		end
	end
	for _ in pairs(unknownAt) do
		unknown = unknown + 1
	end
	return { ok = ok, no = no, unknown = unknown, client = CLIENT, texts = Texts().source }
end

-- item data arriving: an item not known yet is read again
ns.On("GET_ITEM_INFO_RECEIVED", function(_, id)
	if id and unknownAt[id] then
		unknownAt[id] = nil
	end
end)

------------------------------------------------------------------------
-- Who can disenchant
------------------------------------------------------------------------

-- the enchanters of the account on the realm and side of this character
-- (the mail goes there): key, who, rank (nil: not known), spell (false:
-- Disenchant not known; nil: not checked, saved by an older version)
function Eco.DEEnchanters()
	local mine = Eco.MarketKey(UnitFactionGroup("player") or "?")
	local list = {}
	for key, v in pairs(DB().enchanters) do
		if type(v) == "table" and v.k == mine then
			list[#list + 1] = { key = key, who = key:match("^[^-]+") or key, rank = tonumber(v.r), spell = v.spell }
		end
	end
	sort(list, function(a, b)
		return a.key < b.key
	end)
	return list
end

-- Who can disenchant an item asking `skill` Enchanting (nil: 1), held by
-- `holder` (a character key, default: this one), soulbound or not: can,
-- how (or why not), the enchanter
function Eco.DEWho(skill, holder, soulbound, list)
	holder = holder or ns.CharKey()
	list = list or Eco.DEEnchanters()
	skill = skill or 1
	if #list == 0 then
		return false, "no enchanter of your account on this realm and side yet (log on it once)"
	end
	local best, reasons = nil, {}
	for _, en in ipairs(list) do
		local reason
		if en.spell == false then
			reason = en.who .. " does not know Disenchant"
		elseif not en.rank then
			reason = en.who .. ": Enchanting rank not known (log on it, open its profession window)"
		elseif en.rank < skill then
			reason = format("%s: Enchanting %d, %d needed", en.who, en.rank, skill)
		elseif soulbound and en.key ~= holder then
			reason = "soulbound: cannot be mailed to " .. en.who
		end
		if reason then
			reasons[#reasons + 1] = reason
		elseif en.key == holder then
			return true, format("%s (Enchanting %d)", en.who, en.rank), en
		else
			best = best or en
		end
	end
	if best then
		return true, format("%s (Enchanting %d), sent by mail", best.who, best.rank), best
	end
	return false, concat(reasons, "; ")
end

function Eco.EnchantersText()
	local list = Eco.DEEnchanters()
	if #list == 0 then
		return "|cffff6060No enchanter yet: learn Enchanting (level 5)|r"
	end
	local parts = {}
	for _, en in ipairs(list) do
		if en.spell == false then
			parts[#parts + 1] = en.who .. " |cffff6060(no Disenchant)|r"
		else
			parts[#parts + 1] = en.who .. (en.rank and (" (" .. en.rank .. ")") or " |cffff6060(rank ?)|r")
		end
	end
	return "|cffffd100Enchanter:|r " .. concat(parts, ", ")
end

-- the characters of the account who can disenchant: their Enchanting rank,
-- the Disenchant spell
-- (C_SpellBook first: on Forever IsPlayerSpell / IsSpellKnown only exist
-- through Blizzard's deprecation wrappers)
local function KnowsSpellBook(spell)
	local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
	return C_SpellBook.IsSpellKnown(spell, bank)
end

local function KnowsDisenchant()
	local any = false
	local modern = C_SpellBook and C_SpellBook.IsSpellKnown and KnowsSpellBook
	for _, fn in ipairs({ modern or false, _G.IsPlayerSpell or false, _G.IsSpellKnown or false }) do
		if type(fn) == "function" then
			any = true
			local ok, known = pcall(fn, DISENCHANT)
			if ok and known then
				return true
			end
		end
	end
	if any then
		return false
	end
end

local function CheckEnchanter()
	local e = DB()
	local rank
	if GetProfessions and GetProfessionInfo then
		local list = { GetProfessions() }
		for i = 1, 6 do
			if list[i] then
				local _, _, r, _, _, _, line = GetProfessionInfo(list[i])
				if line == ENCHANTING then
					rank = tonumber(r)
				end
			end
		end
	end
	local spell = KnowsDisenchant()
	-- (the enchanters of your realm and side can receive items by mail)
	if rank ~= nil or spell then
		e.enchanters[ns.CharKey()] = { r = rank, spell = spell, k = Eco.MarketKey(UnitFactionGroup("player") or "?"), t = time() }
	else
		e.enchanters[ns.CharKey()] = nil
	end
	Changed()
	RefreshSoon() -- coalesce profession events before rebuilding the visible plan
end
for _, event in ipairs({ "PLAYER_LOGIN", "SKILL_LINES_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "TRADE_SKILL_SHOW" }) do
	ns.On(event, function()
		ns.Try("economy enchanter", CheckEnchanter)
	end)
end

------------------------------------------------------------------------
-- Disenchants seen: the item locked by the cast, then its loot
------------------------------------------------------------------------

local cast -- { at, link, done }

-- the one item of the bags locked now (the one being disenchanted)
local function LockedItem()
	local C, found, foundGUID = _G.C_Container, nil, nil
	for bag = 0, 5 do
		local n = (C and C.GetContainerNumSlots and C.GetContainerNumSlots(bag)) or (GetContainerNumSlots and GetContainerNumSlots(bag)) or 0
		for slot = 1, n do
			local locked, link
			if C and C.GetContainerItemInfo then
				local info = C.GetContainerItemInfo(bag, slot)
				if type(info) == "table" then
					locked, link = info.isLocked, info.hyperlink
				end
			elseif GetContainerItemInfo then
				local _
				_, _, locked, _, _, _, link = GetContainerItemInfo(bag, slot)
			end
			if locked and link then
				if found then
					return nil -- (two: not sure which)
				end
                found = link
                if ItemLocation and C_Item and C_Item.GetItemGUID then
                    local loc=ItemLocation:CreateFromBagAndSlot(bag,slot)
                    foundGUID=C_Item.GetItemGUID(loc)
                end
			end
		end
	end
	return found, foundGUID
end

local function OnCast(event, unit, ...)
	if unit ~= "player" then
		return
	end
	-- (the spell id: the last argument of these events)
	local n = select("#", ...)
	local spell = n > 0 and select(n, ...) or nil
	if spell ~= DISENCHANT then
		return
	end
	if event == "UNIT_SPELLCAST_SENT" or event == "UNIT_SPELLCAST_START" then
		local link, guid = LockedItem()
		if link or not cast then
			cast = { at = GetTime(), link = link or (cast and cast.link), guid=guid or (cast and cast.guid) }
		end
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		if cast then
			cast.done = GetTime()
		end
	else
		cast = nil
	end
end
for _, event in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }) do
	ns.OnUnit(event, "player", OnCast)
end

function Eco.DESeen()
	local e = DB()
	if type(e.deSeen) ~= "table" then
		e.deSeen = {}
	end
	local s = e.deSeen[CLIENT]
	if type(s) ~= "table" then
		s = { items = {}, lots = {} }
		e.deSeen[CLIENT] = s
	end
	return s
end

local function OnLoot()
	local c = cast
	if not (c and c.done and c.link and GetTime() - c.done <= SEEN_WITHIN) then
		return
	end
	if GetLootSourceInfo then
		local guid = GetLootSourceInfo(1)
		if c.guid and guid and guid ~= c.guid then return end
		if type(guid) == "string" and not guid:find("^Item") then
			return -- (not the loot of an item)
		end
	end
	local mats, parts = {}, {}
	for i = 1, (GetNumLootItems and GetNumLootItems() or 0) do
		local mid = LinkID(GetLootSlotLink and GetLootSlotLink(i))
		if not mid then return end
		local qty = GetLootSlotInfo and select(3, GetLootSlotInfo(i))
		if mid then
			mats[mid] = (mats[mid] or 0) + (tonumber(qty) or 1)
		end
	end
	for mid, q in pairs(mats) do
		parts[#parts + 1] = mid .. "x" .. q
	end
	if #parts == 0 then
		return
	end
	cast = nil -- consumed only after a complete item yield is available
	sort(parts)
	local outcome = concat(parts, ",")
	local id = LinkID(c.link)
	local s = Eco.DESeen()
	local rec = s.items[id] or { n = 0, out = {} }
	s.items[id] = rec
	rec.n, rec.t = rec.n + 1, time()
	rec.out[outcome] = (rec.out[outcome] or 0) + 1
	local def = Eco.DE and Eco.DE.LotOf(Item(id))
	if def then
		local lot = s.lots[def.key] or { n = 0, out = {} }
		s.lots[def.key] = lot
		lot.n = lot.n + 1
		lot.out[outcome] = (lot.out[outcome] or 0) + 1
	end
	Keep(id, "ok", nil, "seen")
    if Eco.DERecordYield then Eco.DERecordYield(c.link,c.guid,mats) end
end
ns.On("LOOT_READY", OnLoot)
ns.On("LOOT_OPENED", OnLoot)

------------------------------------------------------------------------
-- /wc3c eco de <item id or link>
------------------------------------------------------------------------

local STATE_TEXT = { ok = "|cff40ff40CONFIRMED|r disenchantable", no = "|cffff4040CANNOT|r be disenchanted", unknown = "|cffffd100NOT KNOWN|r (never counted as disenchantable)" }
Eco.DE_STATE_TEXT = STATE_TEXT

function Eco.DEExplain(ref)
    -- No argument: inspect a real gear item from this market's last scan.
    if not ref or ref=="" then
        local _,market=DB()
        for key,rec in pairs(market.items or {}) do
            local id=BaseID(key)
            local it=Item(id)
            if rec.s==market.scanId and it and not Rules(it) and not Exception(id) then
                ref=rec.l or it.link or id
                break
            end
        end
    end
	local id = ItemID(tonumber(ref) or ref)
	if not id then
		ns.Print("/wc3c eco de <item id or link>")
		return
	end
	local it = Item(id)
	local state, why, skill, src = Eco.DEState(id)
	ns.Print(format("%s (item %d), client %s:", it and it.link or ("item " .. id), id, CLIENT))
	ns.Print(format("  %s: %s [%s]", STATE_TEXT[state] or state, why or "?", src or "?"))
	if not it then
		ns.Print("  its data is not loaded yet: try again in a moment.")
		return
	end
	ns.Print(format("  quality %s, class %s, item level %s, slot %s, bind %s", tostring(it.quality), tostring(it.class), tostring(it.level),
		tostring(it.equipLoc), tostring(it.bind)))
	local x = EXCEPTIONS[id]
	if x then
		local en = ((GetLocale and GetLocale()) or ""):match("^en")
		ns.Print(format("  exception of client %s (seen on build %s): %s%s", x.version, x.build or "?", x.why,
			x.version ~= VERSION and " |cffff8040- not this client: not applied|r" or ""))
		if en and it.name ~= x.name then
			ns.Print(format("  |cffff8040the exception names it \"%s\", this client \"%s\": check the id|r", x.name, it.name))
		end
	end
	-- (both ways, each one told: which of them shows the disenchant line)
	local t = Texts()
	for _, way in ipairs({ { InfoLines, "tooltip data" }, { ScanLines, "hidden tooltip" } }) do
		local lines, count = way[1](id, it.link)
		if lines then
			local v, vskill, line = Verdict(lines, count or 0)
			ns.Print(format("  %s (%d lines, texts: %s): %s", way[2], count or 0, t.source,
				v and format("\"%s\" -> %s%s", line, v, vskill and (", Enchanting " .. vskill) or "") or "no disenchant line"))

            if not v then
                for i=1,math.min(count or 0,20) do
                    if not ns.IsSecret(lines[i]) and type(lines[i])=="string" then
                        ns.Print(format("    [%d] %s",i,Clean(lines[i])))
                    end
                end
            end
        else
            ns.Print(format("  %s: not available on this client", way[2]))
		end
	end
	local def = Eco.DE and Eco.DE.LotOf(it)
	if def then
		ns.Print(format("  lot: %s, Enchanting %s in the classic table; yield table %s", def.label, tostring(def.skill),
			Eco.DE.Validated(def) and "validated on this client" or "|cffff8040not validated on this client|r"))
		local can, whyWho = Eco.DEWho(skill or def.skill, nil, it.bind == 1)
		ns.Print(format("  who: %s%s", can and "|cff40ff40" or "|cffff6060", whyWho or "?") .. "|r")
	end
	local seen = Eco.DESeen().items[id]
	if seen then
		ns.Print(format("  disenchants of it seen on this client: %d", seen.n))
	end
end
