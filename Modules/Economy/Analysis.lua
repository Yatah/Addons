--[[
	WC3 Console - economy: what the window shows, computed from the price
	history, the auctions of the last scan and your ledger
	  Deals    vendor and resale deals, by category of item
	  Trades   your stock and results per item, the journal
	  Market   which markets are active
	  Crafts   the cost of your recipes against their product
	  Enchant  lots of gear to disenchant
]]

local _, ns = ...
local Eco = ns.Economy
local floor, max, min, abs, format = math.floor, math.max, math.min, math.abs, string.format
local pairs, ipairs = pairs, ipairs
local sort, wipe = table.sort, table.wipe or wipe

local DB, S, Item, BaseID, IsGear = Eco.DB, Eco.S, Eco.Item, Eco.BaseID, Eco.IsGear
local Unpack, Book, BookUnit, Indicators, MarketValue, ProductPrice = Eco.Unpack, Eco.Book, Eco.BookUnit, Eco.Indicators, Eco.MarketValue, Eco.ProductPrice
local Ledger, LedgerStats, DepositPerUnit, Budget = Eco.Ledger, Eco.LedgerStats, Eco.DepositPerUnit, Eco.Budget
local SellPriceOf, Recipes = Eco.SellPriceOf, Eco.Recipes
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant
local HOUR, DAY = Eco.HOUR, Eco.DAY

------------------------------------------------------------------------
-- Deals
--   Vendor  below the vendor price: a sure profit
--   resale  (your method)
--     prudent price  P = min(M14, Q25 of 7 days, your recent sales, the
--                    lowest price left once the cheap auctions are bought)
--     max buy        (P x 0.95 - F) / (1 + return), F: deposits of the
--                    failed posts to cover (per unit)
--     status         Falling (M3 / M14 - 1 < -10 %), Unstable (spread
--                    > 30 %), Stop (your sales: under 30 % within 48 h),
--                    New (< 7 days: tests), Caution (7-13 days or spread
--                    15-30 %: +10 % return), Good, Proven (your sales:
--                    70 % within 48 h)
--     quantity       1 % of the budget per item while testing, 5 % once
--                    proven (stock included), half of the budget kept
--                    free, two days of your sales at most once proven
------------------------------------------------------------------------

local STATUS = {
	vendor = { "Vendor", 0.3, 1, 0.3, 7 },
	proven = { "Proven", 0.3, 1, 0.3, 6 },
	good = { "Good", 0.65, 0.95, 0.45, 5 },
	caution = { "Caution", 1, 0.82, 0, 4 },
	new = { "New", 0.7, 0.7, 0.7, 3 },
	falling = { "Falling", 1, 0.35, 0.35, 2 },
	unstable = { "Unstable", 1, 0.35, 0.35, 1 },
	stop = { "Stop", 1, 0.35, 0.35, 0 },
}
Eco.STATUS = STATUS

local VENDOR_MIN = 20 -- copper

------------------------------------------------------------------------
-- Deals categories: what an item is, from the item class and subclass of
-- the game (not from its name), with exceptions by item id. One category
-- per item; how it is resold (AH or vendor) is a separate filter.
------------------------------------------------------------------------

local CATEGORIES = {
	{ key = "all", label = "All categories" },
	{ key = "mats", label = "Crafting materials", subs = {
		{ key = "herbs", label = "Herbs" },
		{ key = "metal", label = "Ores & bars" },
		{ key = "stones", label = "Stones & gems" },
		{ key = "cloth", label = "Cloth" },
		{ key = "leather", label = "Leather & scales" },
		{ key = "elemental", label = "Elemental" },
		{ key = "other", label = "Other materials" },
	} },
	{ key = "enchanting", label = "Enchanting" },
	{ key = "consumables", label = "Consumables", subs = {
		{ key = "potions", label = "Potions, elixirs, flasks" },
		{ key = "food", label = "Food & drink" },
		{ key = "scrolls", label = "Scrolls" },
		{ key = "enhancements", label = "Item enhancements" },
		{ key = "other", label = "Other consumables" },
	} },
	{ key = "cooking", label = "Cooking & fishing" },
	{ key = "bags", label = "Bags & storage" },
	{ key = "recipes", label = "Recipes & plans" },
	{ key = "gear", label = "Gear" },
	{ key = "utility", label = "Utility & misc parts" },
	{ key = "other", label = "Other" },
}
for _, c in ipairs(CATEGORIES) do
	CATEGORIES[c.key] = c
	for _, s in ipairs(c.subs or {}) do
		c[s.key] = s
	end
end
Eco.CATEGORIES = CATEGORIES

local Category -- (id) -> category, subcategory ("loading": not known yet)
do
	-- Trade Goods (class 7) subclasses
	local TRADE = {
		[0] = { "mats", "other" }, [1] = { "mats", "other" }, -- trade goods, parts
		[2] = { "utility" }, [3] = { "utility" }, [17] = { "utility" }, -- explosives, devices
		[4] = { "mats", "stones" }, [5] = { "mats", "cloth" }, [6] = { "mats", "leather" },
		[7] = { "mats", "metal" }, [8] = { "cooking" }, [9] = { "mats", "herbs" },
		[10] = { "mats", "elemental" }, [11] = { "mats", "other" }, [12] = { "enchanting" },
		[13] = { "mats", "other" }, [16] = { "mats", "other" },
		[14] = { "consumables", "enhancements" }, [15] = { "consumables", "enhancements" }, -- armor / weapon enchantments
	}
	-- Consumable (class 0) subclasses: potion, elixir, flask, scroll, food & drink, item enhancement
	local CONSUMABLE = { [1] = "potions", [2] = "potions", [3] = "potions", [4] = "scrolls", [5] = "food", [6] = "enhancements" }
	local function ByClass(class, sub)
		if class == 0 then
			return "consumables", CONSUMABLE[sub] or "other"
		elseif class == 1 or class == 11 then -- bags, quivers and ammo pouches
			return "bags"
		elseif class == 2 then
			return sub == 20 and "utility" or "gear" -- fishing poles: tools
		elseif class == 3 then
			return "mats", "stones"
		elseif class == 4 then
			return "gear"
		elseif class == 5 or class == 6 or class == 13 or (class == 15 and sub == 1) then
			return "utility" -- spell reagents, ammo, keys
		elseif class == 7 then
			local t = TRADE[sub] or TRADE[0]
			return t[1], t[2]
		elseif class == 8 then
			return "consumables", "enhancements"
		elseif class == 9 then
			return "recipes"
		end
		return "other"
	end
	-- exceptions: the game class does not say what they are for a trader
	local EXCEPTIONS = {}
	for _, id in ipairs({
		10940, 11083, 11137, 11176, 16204, -- dusts
		10938, 10939, 10998, 11082, 11134, 11135, 11174, 11175, 16202, 16203, -- essences
		10978, 11084, 11138, 11139, 11177, 11178, 14343, 14344, 20725, -- shards, Nexus Crystal
	}) do
		EXCEPTIONS[id] = { "enchanting" }
	end
	for _, id in ipairs({
		2835, 2836, 2838, 7912, 12365, -- rough, coarse, heavy, solid, dense stone
		774, 818, 1210, 1206, 1705, 1529, 3864, 7909, 7910, 12361, 12799, 12800, 12364, 12363, 11754, -- gems, Arcane Crystal
		5498, 5500, 7971, 13926, -- pearls
	}) do
		EXCEPTIONS[id] = { "mats", "stones" }
	end

	local cache = {}
	function Category(id)
		local c = cache[id]
		if not c then
			c = EXCEPTIONS[id]
			if not c then
				local _, _, _, _, _, class, sub = GetItemInfoInstant(id)
				if not class then
					-- not known yet: asked, classified at the next refresh
					Eco.RequestItem(id)
					return "loading"
				end
				c = { ByClass(class, sub) }
			end
			cache[id] = c
		end
		return c[1], c[2]
	end
	Eco.Category = Category
end

-- "Crafting materials - Herbs"
function Eco.CategoryLabel(cat, sub)
	local c = CATEGORIES[cat]
	if not c then
		return "Not known yet"
	end
	return c.label .. ((sub and c[sub]) and (" - " .. c[sub].label) or "")
end

local function VendorDeal(key, rec, id, sell)
	local book = Book(key, rec)
	local units, cost, profit = 0, 0, 0
	for j = 1, #book do
		local p, c = Unpack(book[j])
		if p >= sell then
			break
		end
		units, cost, profit = units + c, cost + p * c, profit + (sell - p) * c
	end
	if profit >= VENDOR_MIN then
		local _, days = MarketValue(rec)
		return {
			key = key, id = id, link = rec.l, status = "vendor", price = rec.m, maxBuy = sell, units = units,
			buy = units, cost = cost, resell = sell, profit = profit, potential = profit, days = days,
			listed = rec.q or 0, auctions = rec.n,
		}
	end
end

local function ResaleDeal(key, rec, id, st, stats, budget, freeRoom)
	if rec.u then
		return nil
	end
	local it = Item(id)
	if not it or (st.stackOnly and it.stack <= 1) then
		return nil
	end
	local ind = Indicators(rec)
	local r = st.minReturn / 100
	-- nothing can be a deal above this
	if not ind.m14 or rec.m >= ind.m14 * (1 - Eco.cut) / (1 + r) then
		return nil
	end
	local s = stats[id]
	local status
	if ind.trend and ind.trend < -0.10 then
		status = "falling"
	elseif ind.spread and ind.spread > 0.30 then
		status = "unstable"
	elseif s and s.state == "stop" then
		status = "stop"
	elseif ind.days < 7 then
		status = "new"
	elseif ind.days < 14 or (ind.spread and ind.spread > 0.15) then
		status = "caution"
		r = r + 0.10
	elseif s and s.state == "validated" then
		status = "proven"
	else
		status = "good"
	end
	local risky = status == "falling" or status == "unstable" or status == "stop"
	if risky and not st.showRisky then
		return nil
	end
	local P = ind.m14
	if ind.q25_7 then
		P = min(P, ind.q25_7)
	end
	if s and s.avgSale then
		P = min(P, s.avgSale)
	end
	local deposit, depositKnown = DepositPerUnit(id)
	local F = (s and s.observedF) or st.failures * deposit
	-- the lowest price left once every auction under the max buy price is
	-- bought (only with the auctions of a full scan)
	local exact = S.books[key] ~= nil
	local book = Book(key, rec)
	local maxBuy, competitor
	for _ = 1, 6 do
		maxBuy = (P * (1 - Eco.cut) - F) / (1 + r)
		competitor = nil
		for j = 1, #book do
			local p = Unpack(book[j])
			if p > maxBuy then
				competitor = p
				break
			end
		end
		if exact and competitor and competitor < P then
			P = competitor
		else
			break
		end
	end
	local net, low = P * (1 - Eco.cut) - F, P * 0.9 * (1 - Eco.cut) - F
	local units, dealCost, potential, stress = 0, 0, 0, 0
	for j = 1, #book do
		local p, c = Unpack(book[j])
		if p > maxBuy then
			break
		end
		units, dealCost = units + c, dealCost + p * c
		potential, stress = potential + (net - p) * c, stress + (low - p) * c
	end
	if units == 0 then
		return nil
	end
	local capPct = (risky and 0) or (status == "proven" and 0.05) or 0.01
	local cap = budget * capPct
	local room = max(0, min(cap - (s and s.stockCost or 0), freeRoom))
	local unitLimit = math.huge
	if status == "proven" then
		unitLimit = max(0, floor(2 * s.velocity - s.stock))
	end
	local buy, cost, profit = 0, 0, 0
	for j = 1, #book do
		local p, c = Unpack(book[j])
		if p > maxBuy then
			break
		end
		local n = min(c, unitLimit - buy, floor((room - cost) / p))
		if n <= 0 then
			break
		end
		buy, cost, profit = buy + n, cost + p * n, profit + (net - p) * n
		if n < c then
			break
		end
	end
	return {
		key = key, id = id, link = rec.l, status = status, price = rec.m, maxBuy = maxBuy, units = units,
		buy = buy, cost = cost, dealCost = dealCost, resell = P, profit = profit, potential = potential, stress = stress,
		F = F, deposit = deposit, depositKnown = depositKnown, observedF = s and s.observedF, r = r, ind = ind,
		stats = s, competitor = competitor, exact = exact, budget = budget, capPct = capPct, cap = cap, room = room,
		unitLimit = unitLimit, days = ind.days, listed = rec.q or 0, auctions = rec.n,
	}
end

function Eco.ComputeDeals()
	local e, r = DB()
	Eco.NewPass()
	local st = e.settings
	local stats = LedgerStats()
	local invested = 0
	for _, s in pairs(stats) do
		invested = invested + s.stockCost
	end
	local budget = Budget(st, invested)
	local freeRoom = max(0, budget * 0.5 - invested)
	-- the resale method is chosen here, not after: with "vendor", every
	-- vendor opportunity shows even when an AH resale would earn more
	local method = st.dealMethod
	local out = {}
	for key, rec in pairs(r.items) do
		if rec.s == r.scanId and rec.m then
			local id = BaseID(key)
			local sell = SellPriceOf(id) or 0
			local vendor = method ~= "ah" and rec.m < sell and VendorDeal(key, rec, id, sell) or nil
			local resale = method ~= "vendor" and ResaleDeal(key, rec, id, st, stats, budget, freeRoom) or nil
			-- both methods: the better of the two, one line per item
			local row = vendor
			if resale and (not row or resale.potential > row.profit) then
				row = resale
			end
			if row then
				row.cat, row.sub = Category(id)
				out[#out + 1] = row
			end
		end
	end
	return out
end

-- the deals of the selected category (and subcategory); counts per
-- category of all the deals, per subcategory of the selected category
function Eco.FilterDeals(rows)
	local st = DB().settings
	local cat, sub = st.dealCategory, st.dealSub
	local counts, subCounts, out = { all = #rows }, { all = 0 }, {}
	for _, d in ipairs(rows) do
		counts[d.cat] = (counts[d.cat] or 0) + 1
		if d.cat == cat then
			subCounts.all = subCounts.all + 1
			if d.sub then
				subCounts[d.sub] = (subCounts[d.sub] or 0) + 1
			end
		end
		if cat == "all" or (d.cat == cat and (sub == "all" or d.sub == sub)) then
			out[#out + 1] = d
		end
	end
	return out, counts, subCounts
end

------------------------------------------------------------------------
-- Trades: your stock and results per item
--   advice by the age of the oldest unit (it keeps its purchase date when
--   posted again): 24 h check the price, 48 h under 30 % sold stop
--   buying, 72 h check the prudent price, 7 days sell it off
------------------------------------------------------------------------

local function Advice(s, now)
	local lot = s.oldest
	if lot then
		local age = now - lot.t
		if age > 7 * DAY then
			return "Sell it off", 1, 0.35, 0.35
		elseif age > 48 * HOUR and (lot.s48 or 0) / lot.q < 0.3 then
			return "Stop buying", 1, 0.35, 0.35
		elseif age > 72 * HOUR then
			return "Check the price", 1, 0.6, 0.2
		elseif age > 24 * HOUR then
			return "Check competition", 1, 0.82, 0
		end
		return "OK", 0.7, 0.7, 0.7
	end
	if s.state == "stop" then
		return "Stop buying", 1, 0.35, 0.35
	elseif s.state == "validated" then
		return "Proven", 0.3, 1, 0.3
	end
	return "-", 0.6, 0.6, 0.6
end

function Eco.ComputeTrades()
	Eco.NewPass()
	local now = time()
	local out = {}
	local sum = { stockCost = 0, tied = 0, profit7 = 0, lost7 = 0, evalQty = 0, evalSold = 0 }
	for id, s in pairs(LedgerStats()) do
		sum.stockCost, sum.tied = sum.stockCost + s.stockCost, sum.tied + s.tied
		sum.profit7, sum.lost7 = sum.profit7 + s.profit7, sum.lost7 + s.lost7
		sum.evalQty, sum.evalSold = sum.evalQty + s.evalQty, sum.evalSold + s.evalSold
		-- the items you trade (the rest, junk sold to vendors..., is in the journal)
		if s.bought > 0 or s.sold > 0 or s.posts > 0 or s.lost > 0 then
			local advice, r, g, b = Advice(s, now)
			s.key, s.advice, s.adviceColor = id, advice, { r, g, b }
			s.age = s.oldest and now - s.oldest.t
			out[#out + 1] = s
		end
	end
	Eco.tradeSummary = sum
	return out
end

-- every transaction, newest first:
--   gold  what came in or went out (a sale: price - cut + deposit back;
--         a post: its deposit)
--   profit  a sale: minus the cost of the units taken from your stock;
--           an expiry / cancel: the deposit lost
local KINDS = {
	buyAH = { "Bought (AH)", 1, 1, 1 },
	buyVendor = { "Bought (vendor)", 0.8, 0.8, 0.8 },
	sellAH = { "Sold (AH)", 0.3, 1, 0.3 },
	sellVendor = { "Sold (vendor)", 0.3, 1, 0.3 },
	expired = { "Expired", 1, 0.35, 0.35 },
	cancelled = { "Cancelled", 1, 0.6, 0.2 },
	posted = { "Posted", 0.7, 0.7, 0.7 },
}
Eco.KINDS = KINDS

function Eco.ComputeJournal()
	Eco.NewPass()
	local L = Ledger()
	local out = {}
	for id, lots in pairs(L.lots) do
		for i, lot in ipairs(lots) do
			out[#out + 1] = { key = "b" .. id .. ":" .. i, t = lot.t, kind = lot.v and "buyVendor" or "buyAH", id = id, q = lot.q, gold = -lot.c }
		end
	end
	for i, s in ipairs(L.sales) do
		local net = s.g - s.c
		out[#out + 1] = {
			key = "s" .. i, t = s.t, kind = s.v and "sellVendor" or "sellAH", id = s.id, q = s.q, gold = net + (s.d or 0),
			profit = (s.n or 0) > 0 and (net * s.n / s.q - s.b) or nil,
		}
	end
	for i, f in ipairs(L.fails) do
		out[#out + 1] = { key = "f" .. i, t = f.t, kind = f.k == "cancelled" and "cancelled" or "expired", id = f.id, q = f.q, profit = -(f.d or 0) }
	end
	for i, p in ipairs(L.posts) do
		out[#out + 1] = { key = "p" .. i, t = p.t, kind = "posted", id = p.id, q = p.q, gold = p.d and -p.d }
	end
	return out
end

------------------------------------------------------------------------
-- Market: which markets are active, how their prices and supply move
--   filters  watch (your selection), supply falling (last 3 days 20 %
--            under the last 14), my sales (sold at the auction house),
--            all (stackables of the last scan)
--   a falling supply alone is never a reason to buy
------------------------------------------------------------------------

local SUPPLY_FALLING = -0.2
Eco.SUPPLY_FALLING = SUPPLY_FALLING

-- how much the numbers can be trusted: days of history, tight prices,
-- enough listed, your own sales
local function Confidence(ind, rec, s)
	local score = (ind.days >= 14 and 2) or (ind.days >= 7 and 1) or 0
	if ind.spread then
		score = score + ((ind.spread <= 0.15 and 1) or (ind.spread > 0.30 and -1) or 0)
	end
	if (rec.n or 0) >= 5 or (rec.q or 0) >= 20 then
		score = score + 1
	end
	if s and s.sold > 0 then
		score = score + 1
	end
	return (score >= 4 and 3) or (score >= 2 and 2) or 1
end

function Eco.ToggleWatch(key)
	local watch = DB().watch
	watch[key] = not watch[key] or nil
	Eco.Refresh()
end

function Eco.MarketRow(key, rec, s)
	local e, r = DB()
	local ind = Indicators(rec)
	local current = rec.s == r.scanId
	return {
		key = key, id = BaseID(key), link = rec.l, rec = rec, ind = ind, stats = s,
		price = rec.v or rec.m, trend = ind.trend, listed = current and rec.q or 0, near = current and rec.qn or nil,
		supply = ind.supply, nearSupply = ind.nearSupply, now = current and rec.qdev or nil,
		velocity = s and s.velocity, profit = s and s.profit, confidence = Confidence(ind, rec, s),
		days = ind.days, watched = e.watch[key] == true, seen = rec.t,
	}
end

function Eco.ComputeMarket()
	local e, r = DB()
	Eco.NewPass()
	local filter = e.settings.marketFilter
	local stats = LedgerStats()
	local out = {}
	for key, rec in pairs(r.items) do
		local id = BaseID(key)
		local s = stats[id]
		local include
		if filter == "watch" then
			include = e.watch[key]
		elseif filter == "sales" then
			include = s and s.sold > 0
		elseif filter == "falling" then
			-- gone from the auction house counts too (the supply is 0)
			include = rec.hp ~= nil and not IsGear(id)
			if include then
				local sup = Indicators(rec).supply
				include = sup ~= nil and sup <= SUPPLY_FALLING
			end
		else
			include = rec.s == r.scanId and rec.hp ~= nil and not IsGear(id)
		end
		if include then
			out[#out + 1] = Eco.MarketRow(key, rec, s)
		end
	end
	return out
end

-- one line of context for the Deals tooltip
local function Signed(x)
	return x and format("%+d%%", floor(x * 100 + 0.5)) or "?"
end

function Eco.ContextLine(ind)
	local price = (not ind.trend and "?") or (ind.trend > 0.05 and "rising " .. Signed(ind.trend))
		or (ind.trend < -0.05 and "falling " .. Signed(ind.trend)) or "stable"
	return format("Supply %s  -  Price %s  -  History %d days", Signed(ind.supply), price, ind.days)
end

local craftable = {}
local function BuildCraftable()
	wipe(craftable)
	for _, list in pairs(Recipes()) do
		for _, rc in pairs(list) do
			if rc.o and not craftable[rc.o] then
				craftable[rc.o] = rc
			end
		end
	end
end

-- auction house price of qty units: the cheapest auctions of the last
-- scan, else the market value
local function AuctionUnit(id, qty)
	local _, r = DB()
	local rec = r.items[id]
	if not rec then
		return nil
	end
	if rec.s == r.scanId then
		return BookUnit(id, qty) or rec.m
	end
	return MarketValue(rec) or rec.m
end

local RecipeCost
-- cheapest way to get a reagent: auction house, vendor, or crafted
local function UnitCost(id, qty, depth, seen)
	local best = AuctionUnit(id, qty)
	local src = best and "ah"
	local v = DB().vendor[id]
	if v and (not best or v <= best) then
		best, src = v, "vendor"
	end
	local rc = craftable[id]
	if rc and depth < 2 and not seen[id] then
		seen[id] = true
		local c = RecipeCost(rc, depth + 1, seen)
		seen[id] = nil
		if c then
			c = c / rc.n
			if not best or c < best then
				best, src = c, "craft"
			end
		end
	end
	return best, src
end

Eco.UnitCost = UnitCost

function RecipeCost(rc, depth, seen)
	local total = 0
	for id, qty in pairs(rc.r) do
		local unit = UnitCost(id, qty, depth, seen)
		if not unit then
			return nil
		end
		total = total + unit * qty
	end
	return total
end

function Eco.ComputeCrafts()
	local e = DB()
	Eco.NewPass()
	BuildCraftable()
	local st = e.settings
	local prof = ns.cdb.ecoProfession
	local out = {}
	for name, list in pairs(Recipes()) do
		if not prof or prof == name then
			for rid, rc in pairs(list) do
				local it = Item(rc.o)
				local bound = it and (it.bind == 1 or it.bind == 4)
				if not (st.hideBound and bound) then
					local cost = RecipeCost(rc, 0, { [rc.o] = true })
					local sell, listed, mv, days = ProductPrice(rc.o)
					local net = sell and sell * rc.n * (1 - Eco.cut)
					-- deposits of the failed posts to cover, as for a resale
					local fees = st.failures * DepositPerUnit(rc.o) * rc.n
					local profit = net and cost and net - fees - cost
					if not st.onlyProfit or (profit and profit > 0) then
						out[#out + 1] = {
							key = name .. ":" .. rid, rc = rc, id = rc.o, prof = name, made = rc.n,
							cost = cost, sell = sell, net = net, fees = fees, profit = profit,
							margin = profit and cost and cost > 0 and profit / cost or nil,
							listed = listed, mv = mv, days = days,
						}
					end
				end
			end
		end
	end
	return out
end

------------------------------------------------------------------------
-- Disenchanting (classic tables), by lot. Every item of a lot (its
-- quality, its item level bracket; armor or weapon for the uncommon ones)
-- gives the same materials, by chance: a disenchant is worth its mean (the
-- materials sold at the market price, after the cut) give or take a lot
-- (a shard is rare and worth much more). A lot buys the cheapest auctions
-- with the return asked for (mean / price - 1, each item), as many as
-- needed for the chance of a profit asked for: the exact law of the sum of
-- the disenchants up to EXACT_MAX items, the normal law beyond. A thin
-- margin needs a huge lot (n ~ (z sd / margin)^2): the return keeps lots
-- good. With a capital, a plan sizes the lots to it.
-- Before any of it, each item is checked (Disenchant.lua): only the items
-- the game confirmed as disenchantable, that an enchanter of the account
-- can disenchant, give auctions to a lot. The chance is the model's (the
-- table, the prices of the last scan, the auctions still there): no
-- guarantee. A table not validated on this client gives estimates only,
-- never a lot advised.
------------------------------------------------------------------------


-- A game started before Disenchant.lua was added does not load it (a new
-- file of an addon needs the game restarted, /reload may not do): then
-- nothing can be confirmed, so nothing is advised
if not Eco.DEState then
	local WHY = "restart the game: a new file of the addon (Disenchant.lua) is not loaded"
	Eco.deGen = 0
	Eco.DEState = function()
		return "unknown", WHY, nil, "loading"
	end
	Eco.DEEnchanters = function()
		return {}
	end
	Eco.DEWho = function()
		return false, WHY
	end
	Eco.EnchantersText = function()
		return "|cffff6060Restart the game: a new file of the addon is not loaded|r"
	end
	Eco.DESeen = function()
		return { items = {}, lots = {} }
	end
	Eco.DE_STATE_TEXT = { ok = "confirmed", no = "cannot be disenchanted", unknown = "not known" }
	Eco.DEExplain = function()
		ns.Print(WHY .. ".")
	end
end

do
	-- uncommon: max item level, dust, essence ({ item, quantity min, max }),
	-- shard, chances % (dust, essence, shard) for armor, for weapons,
	-- Enchanting skill, the essence of the weapons when it is not the one
	-- of the armor.
	-- Weapons of item level 21-30 (required level 16-25): Classic gives
	-- Greater Magic Essence, never an Astral one (armor does; their dust
	-- is the one of the armor). Reported on Classic Era since 2019, never
	-- fixed, e.g. Precision Bow (item level 27), Consecrated Wand (30),
	-- Grunt Axe: Blizzard forums 84825 (EU), 506851, 558417, 669014 (US),
	-- Wowhead's Precision Bow page. Its quantity (1-2) and the shard are
	-- taken as the armor's: not told by these reports.
	local UNCOMMON = {
		{ 15, { 10940, 1, 2 }, { 10938, 1, 2 }, nil, { 80, 20, 0 }, { 20, 80, 0 }, 1 }, -- Strange Dust, Lesser Magic Essence
		{ 20, { 10940, 2, 3 }, { 10939, 1, 2 }, 10978, { 75, 20, 5 }, { 20, 75, 5 }, 1 }, -- Greater Magic, Small Glimmering
		{ 25, { 10940, 4, 6 }, { 10998, 1, 2 }, 10978, { 75, 15, 10 }, { 15, 75, 10 }, 25, { 10939, 1, 2 } }, -- Lesser Astral (weapons: Greater Magic)
		{ 30, { 11083, 1, 2 }, { 11082, 1, 2 }, 11084, { 75, 20, 5 }, { 20, 75, 5 }, 50, { 10939, 1, 2 } }, -- Soul Dust, Greater Astral (weapons: Greater Magic), Large Glimmering
		{ 35, { 11083, 2, 5 }, { 11134, 1, 2 }, 11138, { 75, 20, 5 }, { 20, 75, 5 }, 75 }, -- Lesser Mystic, Small Glowing
		{ 40, { 11137, 1, 2 }, { 11135, 1, 2 }, 11139, { 75, 20, 5 }, { 20, 75, 5 }, 100 }, -- Vision Dust, Greater Mystic, Large Glowing
		{ 45, { 11137, 2, 5 }, { 11174, 1, 2 }, 11177, { 75, 20, 5 }, { 20, 75, 5 }, 125 }, -- Lesser Nether, Small Radiant
		{ 50, { 11176, 1, 2 }, { 11175, 1, 2 }, 11178, { 75, 20, 5 }, { 20, 75, 5 }, 150 }, -- Dream Dust, Greater Nether, Large Radiant
		{ 55, { 11176, 2, 5 }, { 16202, 1, 2 }, 14343, { 75, 20, 5 }, { 22, 75, 3 }, 175 }, -- Lesser Eternal, Small Brilliant
		{ 60, { 16204, 1, 2 }, { 16203, 1, 2 }, 14344, { 75, 20, 5 }, { 22, 75, 3 }, 200 }, -- Illusion Dust, Greater Eternal, Large Brilliant
		{ 999, { 16204, 2, 5 }, { 16203, 2, 3 }, 14344, { 75, 20, 5 }, { 22, 75, 3 }, 225 },
	}
	-- rare: max item level, results { item, chance, quantity min, max },
	-- Enchanting skill
	local RARE = {
		{ 25, { { 10978, 1, 1, 1 } }, 25 },
		{ 30, { { 11084, 1, 1, 1 } }, 50 },
		{ 35, { { 11138, 1, 1, 1 } }, 75 },
		{ 40, { { 11139, 1, 1, 1 } }, 100 },
		{ 45, { { 11177, 1, 1, 1 } }, 125 },
		{ 50, { { 11178, 1, 1, 1 } }, 150 },
		{ 55, { { 14343, 1, 1, 1 } }, 175 },
		{ 999, { { 14344, 0.995, 1, 1 }, { 20725, 0.005, 1, 1 } }, 200 }, -- Large Brilliant Shard, Nexus Crystal
	}
	-- epic: from item level 40
	local EPIC = {
		{ 45, { { 11177, 1, 2, 4 } } },
		{ 50, { { 11178, 1, 2, 4 } } },
		{ 55, { { 14343, 1, 2, 4 } } },
		{ 60, { { 20725, 1, 1, 1 } } },
		{ 999, { { 20725, 1, 1, 2 } } },
	}
	local QUALITY = { [2] = "Uncommon", [3] = "Rare", [4] = "Epic" }
	-- 3 lesser essences make a greater one, and back
	local GREATER = { [10938] = 10939, [10998] = 11082, [11134] = 11135, [11174] = 11175, [16202] = 16203 }
	local LESSER = {}
	for l, g in pairs(GREATER) do
		LESSER[g] = l
	end
	-- the law of the sum: exact up to EXACT_MAX items (each sum kept, to the
	-- copper, up to SPARSE_MAX of them: small lots are lumpy; then on a grid
	-- of FINE points per disenchant, twice as coarse whenever the sum needs
	-- more than POINTS), the normal law beyond
	local EXACT_MAX, SPARSE_MAX, FINE, POINTS = 30, 1500, 256, 1024
	local EPS = 1e-9 -- (a chance right on the target: no float noise)

	-- what a material brings once sold at the market price (the lowest
	-- price now, never above the usual one), after the cut; essences: the
	-- better of the lesser and the greater form
	local function SaleValue(id)
		local price = ProductPrice(id)
		return price and price * (1 - Eco.cut)
	end

	local function MaterialValue(id)
		local v = SaleValue(id)
		local g, l = GREATER[id], LESSER[id]
		local other = (g and SaleValue(g)) or (l and SaleValue(l))
		if other then
			other = g and other / 3 or other * 3
			if not v or other > v then
				v = other
			end
		end
		return v
	end
	Eco.MaterialValue = MaterialValue

	-- The yield tables above are the classic ones. One is validated for a
	-- client (its version, GetBuildInfo) once what its disenchants really
	-- give there was checked (the disenchants seen: Disenchant.lua); until
	-- then its lots are estimates, never advised. None is validated on
	-- Forever 1.60 yet.
	local VALIDATED = {
		-- ["1.60.1"] = { ["2:3w"] = true }, (lot keys: quality:row, w / a)
	}
	local function Validated(def)
		local v = VALIDATED[Eco.CLIENT_VERSION]
		return v ~= nil and v[def.key] == true
	end

	-- what the classic tables group (gear of a quality and an item level).
	-- It says nothing of whether the game lets an item be disenchanted:
	-- Eco.DEState
	local function Tabled(it)
		return it ~= nil and (it.class == 2 or it.class == 4) and it.quality >= 2 and it.quality <= 4 and it.level ~= nil
			and it.equipLoc ~= nil and it.equipLoc ~= "" and it.equipLoc ~= "INVTYPE_BODY" and it.equipLoc ~= "INVTYPE_TABARD"
	end

	-- the lot of an item in the classic tables (made once): key, label,
	-- results, skill, the item of its icon
	local defs = {}
	local function LotOf(it)
		if not Tabled(it) then
			return nil
		end
		local q, level, weapon = it.quality, it.level, it.class == 2
		local list = (q == 2 and UNCOMMON) or (q == 3 and RARE) or (q == 4 and level >= 40 and EPIC)
		if not list then
			return nil
		end
		for i, row in ipairs(list) do
			if level <= row[1] then
				local key = q .. ":" .. i .. (q == 2 and (weapon and "w" or "a") or "")
				local def = defs[key]
				if not def then
					local low = (i > 1 and list[i - 1][1] + 1) or (q == 4 and 40)
					local range = (row[1] == 999 and low .. "+") or (low and (low .. "-" .. row[1])) or ("up to " .. row[1])
					def = { key = key, quality = q, order = q * 100 + i * 2 + (weapon and 1 or 0) }
					if q == 2 then
						local p = weapon and row[6] or row[5]
						local essence = (weapon and row[8]) or row[3]
						def.label = format("%s %s, item level %s", QUALITY[q], weapon and "weapon" or "armor", range)
						def.results = { { row[2][1], p[1] / 100, row[2][2], row[2][3] }, { essence[1], p[2] / 100, essence[2], essence[3] } }
						if row[4] and p[3] > 0 then
							def.results[3] = { row[4], p[3] / 100, 1, 1 }
						end
						def.skill, def.icon = row[7], row[2][1]
					else
						def.label = format("%s, item level %s", QUALITY[q], range)
						def.results, def.skill, def.icon = row[2], row[3], row[2][1][1]
					end
					defs[key] = def
				end
				return def
			end
		end
	end

	-- one disenchant: outcomes { value, chance }, mean, standard deviation,
	-- a material without a price (counted 0)
	local function Outcomes(def)
		local out, mean, sq, missing = {}, 0, 0, false
		for _, r in ipairs(def.results) do
			local v = MaterialValue(r[1])
			if not v then
				missing, v = true, 0
			end
			local n = r[4] - r[3] + 1
			for q = r[3], r[4] do
				local value, chance = q * v, r[2] / n
				out[#out + 1] = { value, chance }
				mean, sq = mean + value * chance, sq + value * value * chance
			end
		end
		return out, mean, math.sqrt(max(0, sq - mean * mean)), missing
	end

	-- the normal law: chance of a value under z standard deviations
	local function Phi(z)
		local x = abs(z) / math.sqrt(2)
		local t = 1 / (1 + 0.3275911 * x)
		local erf = 1 - ((((1.061405429 * t - 1.453152027) * t + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * math.exp(-x * x)
		return z >= 0 and (1 + erf) / 2 or (1 - erf) / 2
	end

	-- the sums kept one by one (value in copper -> chance): one more
	-- disenchant, the count of sums
	local function AddSparse(sums, values, chances)
		local out, count = {}, 0
		for s, p in pairs(sums) do
			for i = 1, #values do
				local v = s + values[i]
				local was = out[v]
				if not was then
					count = count + 1
				end
				out[v] = (was or 0) + p * chances[i]
			end
		end
		return out, count
	end

	-- chance that the sum is above `value`; the value under which `q` of it lies
	local function SparseAbove(sums, value)
		local p = 0
		for s, c in pairs(sums) do
			if s > value then
				p = p + c
			end
		end
		return p
	end

	local function SparseUnder(sums, q)
		local list = {}
		for s in pairs(sums) do
			list[#list + 1] = s
		end
		sort(list)
		local acc = 0
		for i = 1, #list do
			acc = acc + sums[list[i]]
			if acc >= q then
				return list[i]
			end
		end
		return list[#list]
	end

	-- the sum on a grid of `res` copper: dist[i] is the chance of
	-- (i - 1) * res; each value split between its two nearest points (the
	-- mean is kept)
	local function ToGrid(sums, res)
		local dist, top = {}, 0
		for s in pairs(sums) do
			top = max(top, s)
		end
		for i = 1, floor(top / res) + 2 do
			dist[i] = 0
		end
		for s, p in pairs(sums) do
			local x = s / res
			local lo = floor(x)
			local f = x - lo
			dist[lo + 1] = dist[lo + 1] + p * (1 - f)
			if f > 0 then
				dist[lo + 2] = dist[lo + 2] + p * f
			end
		end
		return dist
	end

	-- the same sum on a grid twice as coarse
	local function Coarser(dist)
		local out = {}
		for i = 1, floor((#dist - 1) / 2) + 2 do
			out[i] = 0
		end
		for i = 1, #dist do
			local a, j = dist[i], floor((i - 1) / 2) + 1
			if i % 2 == 1 then
				out[j] = out[j] + a
			else
				out[j], out[j + 1] = out[j] + a / 2, out[j + 1] + a / 2
			end
		end
		return out
	end

	-- one disenchant on the grid: { offset, chance, ... }, span: the
	-- largest offset
	local function OneOn(outcomes, res)
		local grid, one = {}, { span = 0 }
		for _, o in ipairs(outcomes) do
			local x = o[1] / res
			local lo = floor(x)
			local f = x - lo
			grid[lo] = (grid[lo] or 0) + o[2] * (1 - f)
			if f > 0 then
				grid[lo + 1] = (grid[lo + 1] or 0) + o[2] * f
			end
		end
		for offset, chance in pairs(grid) do
			one[#one + 1], one[#one + 2] = offset, chance
			one.span = max(one.span, offset)
		end
		return one
	end

	local function AddOne(dist, one)
		local out = {}
		for i = 1, #dist + one.span do
			out[i] = 0
		end
		for i = 1, #dist do
			local a = dist[i]
			if a > 1e-12 then
				for j = 1, #one, 2 do
					local k = i + one[j]
					out[k] = out[k] + a * one[j + 1]
				end
			end
		end
		return out
	end

	local function Above(dist, res, value)
		local t, p = value / res, 0
		for i = #dist, 1, -1 do
			if i - 1 <= t then
				break
			end
			p = p + dist[i]
		end
		return p
	end

	local function Under(dist, res, q)
		local acc = 0
		for i = 1, #dist do
			acc = acc + dist[i]
			if acc >= q then
				return (i - 1) * res
			end
		end
		return (#dist - 1) * res
	end

	-- The law of a sum of disenchants (of one lot or of several), added one
	-- by one: each sum kept to the copper while they are few, then on a grid
	-- (the disenchants of each lot on it, made again whenever it gets
	-- coarser)
	local Sum = {}
	Sum.__index = Sum

	local function NewSum()
		return setmetatable({ sums = { [0] = 1 }, top = 0, ones = {} }, Sum)
	end

	-- the values of the disenchants of a lot, to the copper below (a sum on
	-- the cost is no profit)
	local function Prepare(lot)
		local values, chances, top = {}, {}, 0
		for i, o in ipairs(lot.outcomes) do
			values[i], chances[i] = floor(o[1]), o[2]
			top = max(top, o[1])
		end
		lot.values, lot.chances, lot.top = values, chances, top
	end

	function Sum:Add(lot)
		self.top = max(self.top, lot.top)
		if self.sums then
			local count
			self.sums, count = AddSparse(self.sums, lot.values, lot.chances)
			if count > SPARSE_MAX then
				self.res = max(1, self.top / FINE)
				self.dist, self.sums = ToGrid(self.sums, self.res), nil
			end
			return
		end
		local one = self.ones[lot] or OneOn(lot.outcomes, self.res)
		while #self.dist + one.span > POINTS do
			self.dist, self.res = Coarser(self.dist), self.res * 2
			wipe(self.ones)
			one = OneOn(lot.outcomes, self.res)
		end
		self.ones[lot] = one
		self.dist = AddOne(self.dist, one)
	end

	-- chance of a sum above `value`; the value under which `q` of it lies
	function Sum:Above(value)
		if self.sums then
			return SparseAbove(self.sums, value)
		end
		return Above(self.dist, self.res, value)
	end

	function Sum:Under(q)
		if self.sums then
			return SparseUnder(self.sums, q)
		end
		return Under(self.dist, self.res, q)
	end

	-- How many of the offers (unit prices with the return, cheapest first)
	-- to buy for the chance `target`: need, its cost, its chance, the profit
	-- 1 time out of 10 under low / over high; the chance and cost of all of
	-- them; chances[k]: the chance of the k cheapest
	local function Evaluate(lot, target, minProfit)
		local prices, mean, sd = lot.prices, lot.mean, lot.sd
		local n = #prices
		local sum = NewSum()
		local r, cost = { chances = {} }, 0
		for k = 1, n do
			cost = cost + prices[k]
			local chance, low, high
			-- (once the lot is found among more than EXACT_MAX: the normal
			-- law for all of them)
			if k <= EXACT_MAX and (not r.need or n <= EXACT_MAX) then
				sum:Add(lot)
				chance = sum:Above(cost)
				if not r.need and chance >= target - EPS and k * mean - cost >= minProfit then
					low, high = sum:Under(0.1) - cost, sum:Under(0.9) - cost
				end
			else
				local s = sd * math.sqrt(k)
				chance = s > 0 and Phi((k * mean - cost) / s) or 1
				low, high = k * mean - 1.2816 * s - cost, k * mean + 1.2816 * s - cost
			end
			r.chances[k] = chance
			if not r.need and chance >= target - EPS and k * mean - cost >= minProfit then
				r.need, r.cost, r.chance, r.low, r.high = k, cost, chance, low, high
			end
			r.allCost, r.allChance = cost, chance
		end
		return r
	end

	-- A plan for a capital: every lot safe on its own (its `need` cheapest
	-- auctions, then each dearer one while it stays as safe), the best
	-- returns first, every lot together, until the capital is spent (the
	-- most expected profit for it); counts: lot key -> how many of its
	-- cheapest; smallest: the cost of the cheapest safe lot. Its chance:
	-- the law of the sum of all its disenchants (exact up to PLAN_EXACT of
	-- them, the normal law beyond)
	local PLAN_EXACT = 60
	local lastPlan

	local function BuildPlan(list, capital, target)
		local parts = { capital, target }
		for _, lot in ipairs(list) do
			parts[#parts + 1] = lot.def.key .. ":" .. lot.sig
		end
		local sig = table.concat(parts, ",")
		if lastPlan and lastPlan.sig == sig then
			return lastPlan
		end
		local pool, smallest = {}, nil
		for _, lot in ipairs(list) do
			local ev = lot.r
			if ev.need then
				-- its safe block, then its other auctions (dearer: after it)
				pool[#pool + 1] = { ev.need * lot.mean / ev.cost, ev.cost, lot, ev.need }
				smallest = min(smallest or ev.cost, ev.cost)
				for i = ev.need + 1, #lot.prices do
					local p = lot.prices[i]
					pool[#pool + 1] = { lot.mean / p, p, lot, i }
				end
			end
		end
		sort(pool, function(x, y)
			if x[1] ~= y[1] then
				return x[1] > y[1]
			elseif x[3] ~= y[3] then
				return x[3].def.order < y[3].def.order
			end
			return x[4] < y[4]
		end)
		local plan = { sig = sig, capital = capital, counts = {}, items = 0, lots = 0, cost = 0, value = 0, smallest = smallest }
		-- the best returns first while the capital lasts. A lot is judged on
		-- its last count only (small lots are lumpy: 2 items can be less safe
		-- than 1 or 5): under the chance, it goes back to its last safe count
		-- and stays there, the capital given back goes to the others
		local counts, frozen, byKey, left = plan.counts, {}, {}, capital
		for _, lot in ipairs(list) do
			byKey[lot.def.key] = lot
		end
		repeat
			for _, o in ipairs(pool) do
				local lot, k = o[3], o[4]
				local key = lot.def.key
				local have = counts[key]
				if o[2] <= left and not frozen[key] and ((not have and k == lot.r.need) or have == k - 1) then
					counts[key], left = k, left - o[2]
				end
			end
			local again = false
			for key, k in pairs(counts) do
				local lot = byKey[key]
				local ev = lot.r
				if ev.chances[k] < target - EPS then
					local j = k - 1
					while j > ev.need and ev.chances[j] < target - EPS do
						j = j - 1
					end
					for i = j + 1, k do
						left = left + lot.prices[i]
					end
					counts[key], frozen[key], again = j, true, true
				end
			end
		until not again
		local var = 0
		for _, lot in ipairs(list) do
			local k = counts[lot.def.key]
			if k then
				local cost = 0
				for i = 1, k do
					cost = cost + lot.prices[i]
				end
				plan.items, plan.lots, plan.cost, plan.value = plan.items + k, plan.lots + 1, plan.cost + cost, plan.value + k * lot.mean
				var = var + k * lot.sd * lot.sd
			end
		end
		plan.left, plan.profit = capital - plan.cost, plan.value - plan.cost
		if plan.items > 0 then
			if plan.items <= PLAN_EXACT then
				local sum = NewSum()
				for _, lot in ipairs(list) do
					for _ = 1, counts[lot.def.key] or 0 do
						sum:Add(lot)
					end
				end
				plan.chance, plan.low, plan.high = sum:Above(plan.cost), sum:Under(0.1) - plan.cost, sum:Under(0.9) - plan.cost
			else
				local s = math.sqrt(var)
				plan.chance = s > 0 and Phi(plan.profit / s) or 1
				plan.low, plan.high = plan.profit - 1.2816 * s, plan.profit + 1.2816 * s
			end
		end
		lastPlan = plan
		return plan
	end

	local results = {} -- lot key -> { sig, evaluation }

	-- a lot of the classic tables, before its items
	local function NewLot(def, gain)
		local lot = { def = def, offers = {}, items = {}, excluded = {}, whole = 0 }
		lot.outcomes, lot.mean, lot.sd, lot.missing = Outcomes(def)
		lot.most = lot.mean / gain -- the highest price with the return
		Prepare(lot)
		return lot
	end

	-- Lots: the items of the last scan by lot of the classic tables. Each
	-- item is checked first: confirmed by the game (Eco.DEState), an
	-- enchanter of yours can disenchant it (Eco.DEWho: its rank known and
	-- high enough, by mail when it is another character). Only then do its
	-- auctions under the max price go to its lot; the others are kept aside
	-- with their reason (lot.excluded, shown in the tooltip), never in its
	-- quantity, its cost or its profit. A lot is advised only with a yield
	-- table validated on this client, safe enough (with a capital: in its
	-- plan); else d.status tells why not. Returns the lots (the advised ones,
	-- every lot with "Every lot"), how many are advised, the plan of the
	-- capital (advised lots only), info: what was left out (counts)
	function Eco.ComputeEnchant()
		local e, r = DB()
		Eco.NewPass()
		local st = e.settings
		local target, gain, capital = st.deChance / 100, 1 + st.deReturn / 100, st.deCapital
		local me, enchanters = ns.CharKey(), Eco.DEEnchanters()
		local lots, info = {}, { loading = 0, estimates = 0, excluded = 0, ok=0, no=0, unknown=0 }
		for key, rec in pairs(r.items) do
			if rec.s == r.scanId and rec.m then
				local id = BaseID(key)
				local it = Item(id)
				local def = LotOf(it)
				if not it and IsGear(id) then
					info.loading = info.loading + 1
				end
				if def then
					local lot = lots[def.key]
					if not lot then
						lot = NewLot(def, gain)
						lots[def.key] = lot
					end
					local entry = { key = key, id = id, link = rec.l or it.link, units = 0 }
					entry.state, entry.why, entry.skill = Eco.DEState(id)
                    if Eco.DEExcluded and Eco.DEExcluded(id,entry.link,it) then entry.state,entry.why="no","Excluded by you" end
                    info[entry.state]=(info[entry.state] or 0)+1
					if entry.state == "ok" then
						local can, how = Eco.DEWho(entry.skill or def.skill, me, it.bind == 1, enchanters)
						if can then
							entry.how = how
						else
							entry.state, entry.why = "who", how
						end
					end
					-- (worth more whole: its resale beats a disenchant, Deals)
					local worth = MarketValue(rec)
					if entry.state == "ok" and lot.mean > 0 and worth and worth * (1 - Eco.cut) > lot.mean then
						entry.state, entry.why = "whole", "worth more sold whole (Deals)"
						lot.whole = lot.whole + 1
					end
					local book = Book(key, rec)
					for j = 1, #book do
						local p, c = Unpack(book[j])
						if p > lot.most or p >= lot.mean then
							break
						end
						entry.units, entry.top = entry.units + c, p
						if entry.state == "ok" then
							for _ = 1, c do
								lot.offers[#lot.offers + 1] = { p, key, entry.link }
							end
						end
					end
					if entry.state == "ok" then
						lot.items[#lot.items + 1] = entry
					else
						lot.excluded[#lot.excluded + 1] = entry
						if entry.units > 0 then
							info.excluded = info.excluded + entry.units
						end
					end
				end
			end
		end
		local list, modeled = {}, {}
		for lkey, lot in pairs(lots) do
			local def = lot.def
			sort(lot.offers, function(a, b)
				return a[1] < b[1]
			end)
			local prices, total = {}, 0
			for i, o in ipairs(lot.offers) do
				prices[i] = o[1]
				total = total + o[1]
			end
			lot.prices = prices
			-- (a new answer of the game changes the items of a lot: Eco.deGen)
			lot.sig = format("%d:%d:%d:%d:%.0f:%.1f:%.1f", Eco.stamp, Eco.deGen, target * 100, #prices, total, lot.mean, lot.sd)
			lot.sig = lot.sig .. ":" .. tostring(st.deMinProfit)
			local cached = results[lkey]
			if not (cached and cached.sig == lot.sig) then
				cached = { sig = lot.sig, r = Evaluate(lot, target, st.deMinProfit) }
				results[lkey] = cached
			end
			lot.r = cached.r
			lot.validated = Validated(def)
			lot.can, lot.how = Eco.DEWho(def.skill, me, false, enchanters)
			list[#list + 1] = lot
			if #prices > 0 and not lot.missing then
                modeled[#modeled+1]=lot
				if not lot.validated then info.estimates = info.estimates + 1 end
			end
		end
		local plan
        sort(modeled,function(a,b) return a.def.order < b.def.order end)
        local modelPlan = capital > 0 and BuildPlan(modeled,capital,target) or nil
        plan=modelPlan
        if plan then
            plan.estimated=false
            for _,lot in ipairs(modeled) do
                if plan.counts[lot.def.key] and not lot.validated then plan.estimated=true end
            end
        end
        info.modelPlan = modelPlan
        info.modelLots = 0
		local out, good = {}, 0
		for _, lot in ipairs(list) do
			local def, ev, prices = lot.def, lot.r, lot.prices
			local d = {
				key = def.key, label = def.label, quality = def.quality, order = def.order, icon = def.icon, skill = def.skill,
				results = def.results, mean = lot.mean, sd = lot.sd, missing = lot.missing, whole = lot.whole,
				available = #prices, need = ev.need, offers = lot.offers, items = lot.items, excluded = lot.excluded,
				allCost = ev.allCost, allChance = ev.allChance, minReturn = st.deReturn, most = lot.most, target = target,
				validated = lot.validated, can = lot.can, how = lot.how, plan = plan,
			}
			local activePlan = plan
            local k = activePlan and activePlan.counts[def.key]
			if k then
				-- in the plan: its k cheapest
				local cost = 0
				for i = 1, k do
					cost = cost + prices[i]
				end
				d.buy, d.planned, d.cost, d.chance = k, true, cost, ev.chances[k]
			else
				d.buy, d.cost = ev.need, ev.need and ev.cost or ev.allCost
				d.chance, d.low, d.high = ev.need and ev.chance or ev.allChance, ev.low, ev.high
			end
			if activePlan and not k then d.buy,d.cost,d.chance=0,0,0 end
            local n = d.buy or #prices
			d.profit = d.cost and (n * lot.mean - d.cost)
			d.ret = d.cost and d.cost > 0 and d.profit / d.cost or nil
			d.avg = d.cost and n > 0 and d.cost / n or nil -- the price the lot is computed on
			-- advised: confirmed items an enchanter of yours can disenchant, a
			-- yield table validated on this client, safe enough
			if #prices == 0 then
				d.ok, d.status = false, #lot.excluded > 0 and "excluded" or "none"
			elseif not lot.validated then
				d.ok, d.status = false, "estimate"
			elseif plan then
				d.ok = k ~= nil
				d.status = d.ok and "advised" or "outside"
			else
				d.ok = ev.need ~= nil and d.profit >= st.deMinProfit
				d.status = d.ok and "advised" or "unsafe"
			end
			d.modelReady = not lot.missing and (d.buy or 0)>0 and d.profit>=st.deMinProfit
                and d.chance>=target-EPS and (not activePlan or (activePlan.chance or 0)>=target-EPS)
            if d.modelReady and not d.validated then info.modelLots=info.modelLots+1 end
            if d.ok and not d.modelReady then d.ok=false; d.status="unsafe" end
            if d.ok then
                good = good + 1
			end
			if d.ok or d.modelReady or st.deAll then
				out[#out + 1] = d
			end
		end
		Eco.deReport=info
        return out, good, plan, info
	end

	-- (for the crafts to disenchant: Synergy; the console's checks of an item)
	Eco.DE = {
		LotOf = LotOf, Outcomes = Outcomes, Prepare = Prepare, NewSum = NewSum, Phi = Phi, Validated = Validated,
		VALIDATED = VALIDATED, EXACT = PLAN_EXACT, EPS = EPS,
	}
end
