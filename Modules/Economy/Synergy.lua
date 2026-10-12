--[[
	WC3 Console - economy: crafts and disenchanting together (Synergy)
	  gold   craft, disenchant, sell the materials: the crafts of the
	         account whose product can be disenchanted, how many your
	         capital makes and the chance of a profit (a disenchant gives
	         its materials by chance), the shopping list
	  level  the recipes that still give skill points, by their cost per
	         point: their materials less what the product brings back
	         (disenchanted, else to a vendor)
	A crafter and an enchanter can be one character or two of the same
	realm and side (the items go by mail; a soulbound one stays with its
	crafter). Each character's recipes, their colours and the rank of its
	profession are saved when its profession window opens (Scan).
	A product is disenchanted only when the game confirmed it can be and an
	enchanter of the account can do it (Disenchant.lua, as in Enchant); a
	yield table not validated on this client gives estimates, never a craft
	advised.
]]

local _, ns = ...
local Eco = ns.Economy
local floor, ceil, max, min, format = math.floor, math.ceil, math.max, math.min, string.format
local pairs, ipairs, type = pairs, ipairs, type
local sort, wipe = table.sort, table.wipe or wipe

local DB, Item, Book, Unpack, ProductPrice = Eco.DB, Eco.Item, Eco.Book, Eco.Unpack, Eco.ProductPrice
local SellPriceOf, DepositPerUnit = Eco.SellPriceOf, Eco.DepositPerUnit
local DE = Eco.DE

local MAX_CRAFTS = 200 -- crafts looked at for one recipe
local DEPTH = 2 -- reagents crafted themselves: so deep at most
-- chance of a skill point by the colour of a recipe (classic: sure when
-- orange, then down from yellow to grey; the mean of each colour)
local SKILL_UP = { [0] = 1, [1] = 0.75, [2] = 0.25, [3] = 0 }
Eco.SKILL_UP = SKILL_UP

------------------------------------------------------------------------
-- Crafters and enchanters of the account
------------------------------------------------------------------------

-- the ranks of this character's professions now (the colours of its
-- recipes were seen at the rank of their window); the recipes saved
-- before the account kept them
local function LiveRanks()
	local e = DB()
	local key = ns.CharKey()
	local c = e.crafters[key]
	if type(c) ~= "table" then
		c = {}
		e.crafters[key] = c
	end
	c.k = Eco.MarketKey(UnitFactionGroup("player") or "?")
	c.p = type(c.p) == "table" and c.p or {}
	for name, list in pairs(Eco.Recipes()) do
		if not c.p[name] then
			c.p[name] = { list = list }
		end
	end
	if not next(c.p) then
		e.crafters[key] = nil
		return
	end
	if GetProfessions and GetProfessionInfo then
		local live, list = {}, { GetProfessions() }
		for i = 1, 6 do
			if list[i] then
				local name, _, rank = GetProfessionInfo(list[i])
				if name then
					live[name] = rank
				end
			end
		end
		c.live = live
	end
end
for _, event in ipairs({ "PLAYER_LOGIN", "SKILL_LINES_CHANGED", "TRADE_SKILL_SHOW" }) do
	ns.On(event, function()
		ns.Try("economy ranks", LiveRanks)
	end)
end

-- the crafters of this market, one per profession: key ("character|
-- profession"), char, who (its name), prof, p (rank r, max m, recipes
-- list), live (its rank now)
function Eco.Crafters()
	local e = DB()
	local mine = Eco.MarketKey(UnitFactionGroup("player") or "?")
	local out = {}
	for key, c in pairs(e.crafters) do
		if type(c) == "table" and c.k == mine and type(c.p) == "table" then
			for prof, p in pairs(c.p) do
				if type(p) == "table" and type(p.list) == "table" then
					out[#out + 1] = {
						key = key .. "|" .. prof, char = key, who = key:match("^[^-]+") or key, prof = prof, p = p,
						live = type(c.live) == "table" and c.live[prof] or nil,
					}
				end
			end
		end
	end
	sort(out, function(a, b)
		return a.key < b.key
	end)
	return out
end

-- (who can disenchant: Eco.DEWho, Disenchant.lua; the enchanters of this
-- market: Eco.DEEnchanters)

------------------------------------------------------------------------
-- Costs: many crafts empty the cheap auctions
------------------------------------------------------------------------

local CraftCost

-- what qty units of an item cost now, the cheapest way: the auction house
-- (its cheapest qty units listed; not when fewer are listed), a vendor or
-- a craft of it by the same crafter (own: product -> recipe); the total,
-- the source, the dearest unit price paid (auction house, vendor)
local function BulkCost(id, qty, own, depth, seen)
	local e, r = DB()
	local best, src, top
	local rec = r.items[id]
	if rec and rec.s == r.scanId and rec.m and (rec.q or 0) >= qty then
		local book = Book(id, rec)
		local need, cost, last = qty, 0, rec.m
		for j = 1, #book do
			local p, c = Unpack(book[j])
			local take = min(c, need)
			cost, need, last = cost + p * take, need - take, p
			if need <= 0 then
				break
			end
		end
		best, src, top = cost + last * need, "ah", last
	end
	local v = e.vendor[id]
	if v and (not best or v * qty <= best) then
		best, src, top = v * qty, "vendor", v
	end
	local rc = own[id]
	if rc and depth < DEPTH and not seen[id] then
		seen[id] = true
		local c = CraftCost(rc, ceil(qty / rc.n), own, depth + 1, seen)
		seen[id] = nil
		if c and (not best or c < best) then
			best, src, top = c, "craft", nil
		end
	end
	return best, src, top
end
Eco.BulkCost = BulkCost

-- the materials of `crafts` crafts of a recipe (nil: not all to be had)
function CraftCost(rc, crafts, own, depth, seen)
	local total = 0
	for id, q in pairs(rc.r) do
		local c = BulkCost(id, q * crafts, own, depth or 0, seen or { [rc.o] = true })
		if not c then
			return nil
		end
		total = total + c
	end
	return total
end
Eco.CraftCost = CraftCost

-- how many crafts the materials to be had allow (limit at most)
local function CanMake(rc, own, limit)
	if not CraftCost(rc, 1, own) then
		return 0
	elseif CraftCost(rc, limit, own) then
		return limit
	end
	local lo, hi = 1, limit
	while hi - lo > 1 do
		local mid = floor((lo + hi) / 2)
		if CraftCost(rc, mid, own) then
			lo = mid
		else
			hi = mid
		end
	end
	return lo
end

-- the shopping list of `crafts` crafts, as BulkCost chooses: buy (id ->
-- { qty, cost, src, top: the dearest unit price }), craft (id -> crafts:
-- the reagents to craft first, their own materials in buy)
local function Expand(id, qty, own, depth, seen, list)
	local cost, src, top = BulkCost(id, qty, own, depth, seen)
	if not cost then
		list.missing = true
		return
	end
	if src == "craft" then
		local rc = own[id]
		local crafts = ceil(qty / rc.n)
		list.craft[id] = (list.craft[id] or 0) + crafts
		seen[id] = true
		for rid, q in pairs(rc.r) do
			Expand(rid, q * crafts, own, depth + 1, seen, list)
		end
		seen[id] = nil
		return
	end
	local b = list.buy[id]
	if not b then
		b = { qty = 0, cost = 0, src = src, top = 0 }
		list.buy[id] = b
	end
	b.qty, b.cost, b.top = b.qty + qty, b.cost + cost, max(b.top, top or 0)
end

function Eco.ShoppingList(rc, crafts, own)
	local list = { buy = {}, craft = {} }
	local seen = { [rc.o] = true }
	for id, q in pairs(rc.r) do
		Expand(id, q * crafts, own, 0, seen, list)
	end
	return list
end

------------------------------------------------------------------------
-- What a product brings
------------------------------------------------------------------------

local lots = {} -- lot key -> its disenchant (this pass)

-- one product: disenchanted (de: only when the game confirmed it can be,
-- Eco.DEState, and an enchanter of the account can do it, Eco.DEWho: by
-- mail unless soulbound, then its crafter only), to a vendor; value and
-- outlet: the better; lot: its disenchant in the classic tables, need: the
-- Enchanting asked, state / why: the check of the item, estimate: its
-- yield table not validated on this client; ah: sold whole at the auction
-- house (after the cut and the deposits of the failed posts), told only
local function Outlets(id, crafter, ench, st)
	local it = Item(id)
	if not it then
		return nil
	end
	local o = { item = it, soulbound = it.bind == 1, vendor = SellPriceOf(id) or 0 }
	local def = DE.LotOf(it)
	if def then
		local lot = lots[def.key]
		if not lot then
			lot = { def = def }
			lot.outcomes, lot.mean, lot.sd, lot.missing = DE.Outcomes(def)
			DE.Prepare(lot)
			lots[def.key] = lot
		end
		local state, why, skill = Eco.DEState(id)
		o.lot, o.need, o.state, o.why = lot, skill or def.skill, state, why
		o.estimate = not DE.Validated(def)
		if state == "ok" then
			o.deOk, o.how = Eco.DEWho(o.need, crafter, o.soulbound, ench)
			if not o.deOk then
				o.why = o.how
			end
		end
		if o.deOk and lot.mean > 0 then
			o.de = lot.mean
		elseif state == "unknown" and lot.mean > 0 then
			-- the game said nothing either way (some clients never do): an
			-- estimate, told as such, never advised; an enchanter must still
			-- be able to
			local can, how = Eco.DEWho(o.need, crafter, o.soulbound, ench)
			if can then
				o.deEst, o.estHow, o.estimate = lot.mean, how, true
			end
		end
	end
	if not o.soulbound then
		local sell = ProductPrice(id)
		if sell then
			o.ah = sell * (1 - Eco.cut) - st.failures * DepositPerUnit(id)
		end
	end
	o.value, o.outlet = o.vendor, "vendor"
	local de = o.de or o.deEst
	if de and de > o.value then
		o.value, o.outlet = de, "de"
	end
	return o
end

-- chance that `n` disenchants of a lot bring more than `cost`, by the
-- normal law (more than DE.EXACT of them: their exact law is summed as the
-- crafts go)
local function Normal(lot, n, cost)
	local s = lot.sd * math.sqrt(n)
	if s <= 0 then
		return n * lot.mean > cost and 1 or 0
	end
	return DE.Phi((n * lot.mean - cost) / s)
end

------------------------------------------------------------------------
-- Gold: crafts to disenchant
------------------------------------------------------------------------

-- A craft to disenchant: its product disenchanted, the materials sold.
-- Crafts: as many as stay profitable (the next one's materials cost less
-- than its disenchant brings: dearer as the cheap auctions go) within the
-- capital, back to the last one with the chance asked for; without a
-- capital, the fewest for that chance
local function GoldRow(cr, rid, rc, own, ench, st, capital, target)
	local o = Outlets(rc.o, cr.char, ench, st)
	if not (o and o.lot) then
		return nil
	end
	local value = o.lot.mean * rc.n -- one craft disenchanted
	local d = {
		key = cr.key .. ":" .. rid, id = rc.o, rc = rc, made = rc.n, crafter = cr, own = own, o = o, value = value,
		one = CraftCost(rc, 1, own), target = target, capital = capital,
	}
	-- (not confirmed by the game: computed all the same, an estimate)
	d.unconfirmed = o.de == nil and o.deEst ~= nil
	-- (sold whole at the auction house, it would bring more: told)
	d.whole = o.ah ~= nil and o.ah * rc.n > value
	if not ((o.de or o.deEst) and d.one) then
		return d -- (no enchanter can, or its materials are not to be had: the tooltip says)
	end
	local sum = DE.NewSum()
	local costs, chances, last, need = {}, {}, 0, nil
	for k = 1, MAX_CRAFTS do
		local c = CraftCost(rc, k, own)
		if not c or c - (costs[k - 1] or 0) > value or (capital > 0 and c > capital) then
			break
		end
		costs[k], last = c, k
		local units = k * rc.n
		if sum and units <= DE.EXACT then
			for _ = 1, rc.n do
				sum:Add(o.lot)
			end
			chances[k] = sum:Above(c)
		else
			sum = nil
			chances[k] = Normal(o.lot, units, c)
		end
		if not need and chances[k] >= target - DE.EPS then
			need = k
		end
		if capital <= 0 and need then
			break
		end
	end
	local k = capital > 0 and last or need
	if k and capital > 0 then
		while k > 0 and chances[k] < target - DE.EPS do
			k = k - 1
		end
		if k == 0 then
			k = nil
		end
	end
	d.need, d.last = need, last
	-- (a yield table not validated on this client: an estimate, never advised)
	d.estimate = o.estimate or d.unconfirmed
	if k then
		d.crafts, d.cost, d.chance, d.ok = k, costs[k], chances[k], not d.estimate
	elseif last > 0 then
		-- (none safe enough: all of them, greyed)
		d.crafts, d.cost, d.chance = last, costs[last], chances[last]
	else
		-- (not even one profitable: one, greyed)
		d.crafts, d.cost = 1, d.one
	end
	d.profit = d.crafts * value - d.cost
	d.ret = d.cost > 0 and d.profit / d.cost or nil
	-- (safe enough under the model and profitable: shown as an estimated craft)
	d.modelReady = k ~= nil and d.profit > 0
	return d
end

------------------------------------------------------------------------
-- Level: the cost of a skill point
------------------------------------------------------------------------

local function LevelRow(cr, rid, rc, own, ench, st)
	if rc.d == 3 then
		return nil -- (grey: no point)
	end
	local o = Outlets(rc.o, cr.char, ench, st)
	local d = {
		key = cr.key .. ":" .. rid, id = rc.o, rc = rc, made = rc.n, crafter = cr, own = own, o = o, level = true,
		color = rc.d, points = rc.d and SKILL_UP[rc.d] * (rc.u or 1), one = CraftCost(rc, 1, own),
	}
	d.back = o and o.value * rc.n or 0
	d.unconfirmed = o ~= nil and o.outlet == "de" and o.de == nil
	if d.one then
		d.net = d.one - d.back
		d.perPoint = d.points and d.points > 0 and d.net / d.points or nil
		d.can = CanMake(rc, own, 100)
	end
	return d
end

------------------------------------------------------------------------
-- The tab
------------------------------------------------------------------------

-- the line under the list: crafters, enchanters, what to refresh
local function Info(crafters, st)
	local parts, warn, label = {}, nil, "All crafters"
	for _, cr in ipairs(crafters) do
		local rank = cr.live or cr.p.r
		parts[#parts + 1] = format("%s %s (%s)", cr.prof, rank and tostring(rank) or "?", cr.who)
		if cr.key == st.synWho then
			label = cr.who .. " - " .. cr.prof
		end
		if st.synWho == "all" or st.synWho == cr.key then
			if not cr.p.r then
				warn = warn or format("Open %s on %s once more: its recipes' colours and rank.", cr.prof, cr.who)
			elseif cr.live and cr.live > cr.p.r then
				warn = format("%s is %d now, its recipes were seen at %d: open it again on %s for their colours.", cr.prof, cr.live, cr.p.r, cr.who)
			end
		end
	end
	local text
	if #parts == 0 then
		text = "|cffffd100Crafters:|r none yet: open your profession windows (each character), they are kept for the account."
	else
		text = "|cffffd100Crafters:|r " .. table.concat(parts, ", ") .. "    " .. Eco.EnchantersText()
	end
	return { label = label, text = text, warn = warn }
end

-- rows of the mode (gold or level), the line under them
function Eco.ComputeSynergy()
	local e = DB()
	Eco.NewPass()
	wipe(lots)
	local st = e.settings
	local target, capital = st.deChance / 100, st.deCapital
	local ench = Eco.DEEnchanters()
	local crafters = Eco.Crafters()
	local level = st.synMode == "level"
	local rows = {}
	for _, cr in ipairs(crafters) do
		if st.synWho == "all" or st.synWho == cr.key then
			-- (its reagents it crafts itself)
			local own = {}
			for _, rc in pairs(cr.p.list) do
				if type(rc) == "table" and rc.o and type(rc.r) == "table" and not own[rc.o] then
					own[rc.o] = rc
				end
			end
			for rid, rc in pairs(cr.p.list) do
				if type(rc) == "table" and rc.o and type(rc.r) == "table" then
					local d
					if level then
						d = LevelRow(cr, rid, rc, own, ench, st)
					else
						d = GoldRow(cr, rid, rc, own, ench, st, capital, target)
					end
					if d then
						rows[#rows + 1] = d
					end
				end
			end
		end
	end
	return rows, Info(crafters, st)
end

-- the crafter shown next: all, then each one
function Eco.NextCrafter()
	local st = DB().settings
	local list = Eco.Crafters()
	local nextKey = list[1] and list[1].key or "all"
	if st.synWho ~= "all" then
		nextKey = "all"
		for i, cr in ipairs(list) do
			if cr.key == st.synWho then
				nextKey = list[i + 1] and list[i + 1].key or "all"
			end
		end
	end
	st.synWho = nextKey
end
