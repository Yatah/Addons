--[[
	WC3 Console - economy: your fortune and your business, as The Goblin
	Ledger shows them (Overview, My Business). Figures only, no frame here.

	Gold: each character's gold is written from its first session with this
	version on, never before (no history is made up):
	  eco.fortune (version 1) = { v, chars = { [character] = { k realm and
	  side, since, money, t, hours = { [hour] = gold at its end }, days =
	  { [day] = gold at its end } } }, goals = { [scope] = copper } }
	  (hours kept 8 days, days 400)
	Three things, never mixed:
	  balance change  the gold on hand moves with everything: sales, repairs,
	                  quests, gold mailed between your characters...
	  revenue         what your sales brought (after the auction house cut)
	  realized profit revenue less a known cost (units of unknown cost are
	                  counted apart, never as free), less the deposits lost
	A scope is "char" (this character), "all" (every character of this
	realm and side) or a character key.
]]

local _, ns = ...
local Eco = ns.Economy
local floor, max, min, format = math.floor, math.max, math.min, string.format
local pairs, ipairs, type, tostring = pairs, ipairs, type, tostring
local sort = table.sort

local DB, Item = Eco.DB, Eco.Item
local HOUR, DAY = Eco.HOUR, Eco.DAY
local FORTUNE_VERSION = 1
local KEEP_HOURS, KEEP_DAYS = 8 * 24, 400

------------------------------------------------------------------------
-- Gold of each character
------------------------------------------------------------------------

local function Store()
	local e = DB()
	local f = e.fortune
	if type(f) ~= "table" then
		f = {}
		e.fortune = f
	end
	f.chars = type(f.chars) == "table" and f.chars or {}
	f.goals = type(f.goals) == "table" and f.goals or {}
	f.v = FORTUNE_VERSION
	return f
end

local session = { points = {} } -- this character, this session: { t, money }

local function Record()
	if not (ns.db and GetMoney) then
		return
	end
	local money = GetMoney()
	if type(money) ~= "number" then
		return
	end
	local f, key, now = Store(), ns.CharKey(), time()
	local c = f.chars[key]
	if type(c) ~= "table" then
		c = { since = now, hours = {}, days = {} }
		f.chars[key] = c
	end
	c.k = Eco.MarketKey(UnitFactionGroup("player") or "?")
	c.money, c.t = money, now
	c.hours[floor(now / HOUR)] = money
	c.days[Eco.Today()] = money
	-- old points: hours of more than 8 days, days of more than 400
	local h0, d0 = floor(now / HOUR) - KEEP_HOURS, Eco.Today() - KEEP_DAYS
	for h in pairs(c.hours) do
		if h < h0 then
			c.hours[h] = nil
		end
	end
	for d in pairs(c.days) do
		if d < d0 then
			c.days[d] = nil
		end
	end
	local p = session.points
	if not session.start then
		session.start = now
	end
	if #p == 0 or p[#p].money ~= money then
		p[#p + 1] = { t = now, money = money }
	end
end
ns.On("PLAYER_LOGIN", function()
	ns.Try("economy fortune", Record)
end)
ns.On("PLAYER_ENTERING_WORLD", function()
	ns.Try("economy fortune", Record)
end)
ns.On("PLAYER_MONEY", function()
	ns.Try("economy fortune", Record)
end)
Eco.RecordFortune = Record

-- the characters of a scope with their gold: { key, who, money, t, since }
function Eco.FortuneChars(scope)
	local f, me = Store(), ns.CharKey()
	local mine = Eco.MarketKey(UnitFactionGroup("player") or "?")
	local out = {}
	for key, c in pairs(f.chars) do
		if type(c) == "table" and c.k == mine and (scope == "all" or key == (scope == "char" and me or scope)) then
			out[#out + 1] = { key = key, who = key:match("^[^-]+") or key, money = c.money, t = c.t, since = c.since, c = c }
		end
	end
	sort(out, function(a, b)
		return a.key < b.key
	end)
	return out
end

-- gold on hand of a scope, the characters counted
function Eco.GoldOnHand(scope)
	local total, list = 0, Eco.FortuneChars(scope)
	for _, ch in ipairs(list) do
		total = total + (ch.money or 0)
	end
	return #list > 0 and total or nil, list
end

-- the start of a range: "session", "7d", "30d"
function Eco.RangeStart(range)
	local now = time()
	if range == "session" then
		return session.start or now
	elseif range == "30d" then
		return now - 30 * DAY
	end
	return now - 7 * DAY
end

local RANGE_LABEL = { session = "this session", ["7d"] = "the last 7 days", ["30d"] = "the last 30 days" }
Eco.RANGE_LABEL = RANGE_LABEL

-- the value of a character at a slot (hours or days): the last one at or
-- before it (nil before its first record)
local function At(points, slot, first)
	if slot < first then
		return nil
	end
	for s = slot, first, -1 do
		if points[s] then
			return points[s]
		end
	end
end

-- Gold history of a scope over a range: points { t, v }, from the moment
-- every character of the scope was followed (since); nil when not enough
-- data (fewer than 2 points)
function Eco.GoldSeries(scope, range)
	local list = Eco.FortuneChars(scope)
	if #list == 0 then
		return nil, { reason = "Your gold is recorded from now on: come back after some play." }
	end
	local since = 0
	for _, ch in ipairs(list) do
		since = max(since, ch.since or 0)
	end
	local now, points = time(), {}
	if range == "session" then
		-- this character's session points, the others as they are
		local others = 0
		for _, ch in ipairs(list) do
			if ch.key ~= ns.CharKey() then
				others = others + (ch.money or 0)
			end
		end
		local mineIn = false
		for _, ch in ipairs(list) do
			mineIn = mineIn or ch.key == ns.CharKey()
		end
		if mineIn then
			for _, p in ipairs(session.points) do
				points[#points + 1] = { t = p.t, v = p.money + others }
			end
		end
		if #points == 1 then
			points[2] = { t = now, v = points[1].v }
		end
	else
		local hourly = range ~= "30d"
		local first = hourly and floor(max(since, now - 7 * DAY) / HOUR) or Eco.Today() - 29
		local last = hourly and floor(now / HOUR) or Eco.Today()
		local sinceSlot = hourly and floor(since / HOUR) or floor((since - (Eco.DayTime(0) - 43200)) / DAY)
		first = max(first, sinceSlot)
		for slot = first, last do
			local sum, all = 0, true
			for _, ch in ipairs(list) do
				local c = ch.c
				local firstSlot = hourly and floor(ch.since / HOUR) or floor((ch.since - (Eco.DayTime(0) - 43200)) / DAY)
				local v = At(hourly and c.hours or c.days, slot, firstSlot)
				if v == nil then
					all = false
					break
				end
				sum = sum + v
			end
			if all then
				points[#points + 1] = { t = hourly and slot * HOUR or Eco.DayTime(slot), v = sum }
			end
		end
	end
	if #points < 2 then
		return nil, { since = since, reason = "Not enough data yet: the history starts " .. date("%m-%d %H:%M", since) .. "." }
	end
	return points, { since = since, chars = #list }
end

-- the savings goal of a scope (copper), set or not
function Eco.SavingsGoal(scope)
	return Store().goals[scope or "char"]
end

function Eco.SetSavingsGoal(scope, copper)
	Store().goals[scope or "char"] = (copper and copper > 0) and floor(copper) or nil
end

------------------------------------------------------------------------
-- Business, from the ledgers of a scope
------------------------------------------------------------------------

local function Scope(scope)
	return scope == "char" and ns.CharKey() or scope or "all"
end

-- what a sale brought: revenue after the cut, its known cost, the result
-- of its units of known cost (nil: none known), units of unknown cost
local function SaleFigures(s)
	local revenue = s.g - (s.c or 0)
	local known = s.n or 0
	local result = known > 0 and (revenue * known / s.q - (s.b or 0)) or nil
	return revenue, known, result, s.q - known
end
Eco.SaleFigures = SaleFigures

-- Overview's figures of a scope over a range (see the head of this file)
function Eco.FortuneSummary(scope, range)
	local key = Scope(scope)
	local from = Eco.RangeStart(range)
	local gold, chars = Eco.GoldOnHand(scope)
	local s = {
		gold = gold, chars = chars, revenue = 0, sales = 0, profit = 0, profitSales = 0, unknownSales = 0, unknownRevenue = 0,
		fees = 0, lost = 0, invested = 0, unknownUnits = 0, stockValue = 0, stockItems = 0, noPrice = 0, ledgers = 0,
	}
	local series = Eco.GoldSeries(scope, range)
	if series then
		s.change = series[#series].v - series[1].v
	end
	local first
	for _, led in ipairs(Eco.Ledgers(key)) do
		local L = led.L
		s.ledgers = s.ledgers + 1
		for _, sale in ipairs(L.sales) do
			first = min(first or sale.t, sale.t)
			if sale.t >= from then
				local revenue, known, result, unknown = SaleFigures(sale)
				s.revenue, s.sales, s.fees = s.revenue + revenue, s.sales + 1, s.fees + (sale.c or 0)
				if result then
					s.profit, s.profitSales = s.profit + result, s.profitSales + 1
				end
				if unknown > 0 then
					s.unknownSales = s.unknownSales + 1
					s.unknownRevenue = s.unknownRevenue + revenue * unknown / sale.q
				end
			end
		end
		for _, fail in ipairs(L.fails) do
			first = min(first or fail.t, fail.t)
			if fail.t >= from then
				s.lost = s.lost + (fail.d or 0)
			end
		end
		for _, lots in pairs(L.lots) do
			for _, lot in ipairs(lots) do
				first = min(first or lot.t, lot.t)
			end
		end
		for id, st in pairs(Eco.LedgerStats(L)) do
			if st.stock > 0 then
				s.invested = s.invested + st.stockCost
				s.unknownUnits = s.unknownUnits + st.unknown
				s.stockItems = s.stockItems + 1
				local price = Eco.ProductPrice(id)
				if price then
					s.stockValue = s.stockValue + price * (1 - Eco.cut) * st.stock
				else
					s.noPrice = s.noPrice + 1
				end
			end
		end
	end
	s.profit = s.profit - s.lost
	s.fees = s.fees + s.lost
	s.ledgerSince = first
	local list = Eco.FortuneChars(scope)
	for _, ch in ipairs(list) do
		s.since = max(s.since or 0, ch.since or 0)
	end
	return s
end

-- Inventory of a scope: one row per character and item in stock
function Eco.Inventory(scope)
	local out, now = {}, time()
	for _, led in ipairs(Eco.Ledgers(Scope(scope))) do
		for id, st in pairs(Eco.LedgerStats(led.L)) do
			if st.stock > 0 then
				local price = Eco.ProductPrice(id)
				local known = st.stock - st.unknown
				out[#out + 1] = {
					key = led.key .. ":" .. id, id = id, who = led.who, char = led.key, qty = st.stock, cost = known > 0 and st.stockCost or nil,
					unit = known > 0 and st.stockCost / known or nil, unknown = st.unknown, value = price and price * (1 - Eco.cut) * st.stock or nil,
					age = st.oldest and now - st.oldest.t or nil, stats = st,
				}
			end
		end
	end
	return out
end

-- the state of each posting, from the mails read after it (same item, same
-- quantity, first come): sold, expired, cancelled; else listed (48 h) or
-- not known (no mail read about it)
function Eco.AuctionList(scope)
	local out, now = {}, time()
	for _, led in ipairs(Eco.Ledgers(Scope(scope))) do
		local L = led.L
		local ends = {}
		for _, s in ipairs(L.sales) do
			if not s.v then
				ends[#ends + 1] = { t = s.t, id = s.id, q = s.q, state = "Sold", g = s.g }
			end
		end
		for _, f in ipairs(L.fails) do
			ends[#ends + 1] = { t = f.t, id = f.id, q = f.q, state = f.k == "cancelled" and "Cancelled" or "Expired" }
		end
		sort(ends, function(a, b)
			return a.t < b.t
		end)
		local posts = {}
		for i, p in ipairs(L.posts) do
			posts[i] = p
		end
		sort(posts, function(a, b)
			return a.t < b.t
		end)
		for i, p in ipairs(posts) do
			local state, at
			for _, e in ipairs(ends) do
				if not e.used and e.id == p.id and e.q == p.q and e.t >= p.t - 60 then
					e.used, state, at = true, e.state, e.t
					break
				end
			end
			if not state then
				state = now - p.t <= 48 * HOUR and "Listed" or "Not known"
			end
			out[#out + 1] = { key = led.key .. ":p" .. i, t = p.t, id = p.id, q = p.q, price = p.p, deposit = p.d, who = led.who, state = state, ended = at }
		end
	end
	return out
end

-- sales of a scope since `from`
function Eco.SalesList(scope, from)
	local out = {}
	for _, led in ipairs(Eco.Ledgers(Scope(scope))) do
		for i, s in ipairs(led.L.sales) do
			if s.t >= (from or 0) then
				local revenue, known, result, unknown = SaleFigures(s)
				out[#out + 1] = {
					key = led.key .. ":s" .. i, t = s.t, id = s.id, q = s.q, who = led.who, gross = s.g, cut = s.c or 0, revenue = revenue,
					cost = known > 0 and s.b or nil, result = result, unknown = unknown, vendor = s.v,
				}
			end
		end
	end
	return out
end

------------------------------------------------------------------------
-- The journal: what was really seen (mails, merchants, postings, mails
-- sent), every character of the scope, newest first. debit / credit: gold
-- out / in for that character; result: profit or loss when it can be
-- computed (nil: not computable, unknown cost)
------------------------------------------------------------------------

local KINDS = {
	buyAH = { "Bought (AH)", "buy" }, buyVendor = { "Bought (vendor)", "buy" },
	sellAH = { "Sold (AH)", "sale" }, sellVendor = { "Sold (vendor)", "sale" },
	posted = { "Posted", "auction" }, expired = { "Expired", "auction" }, cancelled = { "Cancelled", "auction" },
	out = { "Sent to", "transfer" }, ["in"] = { "Received from", "transfer" }, goldOut = { "Gold sent to", "transfer" },
	goldIn = { "Gold from", "transfer" }, gave = { "Mailed away to", "transfer" },
}
Eco.JOURNAL_KINDS = KINDS
Eco.JOURNAL_TYPES = {
	{ value = "all", label = "All operations" }, { value = "buy", label = "Purchases" }, { value = "sale", label = "Sales" },
	{ value = "auction", label = "Auctions" }, { value = "transfer", label = "Transfers" },
}

local PERIODS = { ["24h"] = DAY, ["7d"] = 7 * DAY, ["30d"] = 30 * DAY }
Eco.JOURNAL_PERIODS = {
	{ value = "24h", label = "Last 24 hours" }, { value = "7d", label = "Last 7 days" }, { value = "30d", label = "Last 30 days" },
	{ value = "all", label = "Everything kept" },
}

local function Short(key)
	return key and (key:match("^[^-]+") or key) or "?"
end

function Eco.JournalEntries(scope, period, kind)
	local out, now = {}, time()
	local from = PERIODS[period] and now - PERIODS[period] or 0
	local function Add(e)
		if e.t >= from and (kind == nil or kind == "all" or (KINDS[e.kind] and KINDS[e.kind][2] == kind)) then
			out[#out + 1] = e
		end
	end
	for _, led in ipairs(Eco.Ledgers(Scope(scope))) do
		local L, who = led.L, led.who
		for id, lots in pairs(L.lots) do
			for i, lot in ipairs(lots) do
				-- (a lot received by mail is its transfer, written once in moves)
				if not lot.x then
					Add({ key = led.key .. ":b" .. id .. ":" .. i, t = lot.t, kind = lot.v and "buyVendor" or "buyAH", id = id, q = lot.q, who = who,
						debit = lot.c, ref = lot })
				end
			end
		end
		for i, s in ipairs(L.sales) do
			local revenue, known, result = SaleFigures(s)
			Add({ key = led.key .. ":s" .. i, t = s.t, kind = s.v and "sellVendor" or "sellAH", id = s.id, q = s.q, who = who,
				credit = revenue + (s.d or 0), result = result, partial = known < s.q, ref = s })
		end
		for i, p in ipairs(L.posts) do
			Add({ key = led.key .. ":p" .. i, t = p.t, kind = "posted", id = p.id, q = p.q, who = who, debit = p.d, ref = p })
		end
		for i, f in ipairs(L.fails) do
			Add({ key = led.key .. ":f" .. i, t = f.t, kind = f.k == "cancelled" and "cancelled" or "expired", id = f.id, q = f.q, who = who,
				result = f.d and -f.d or nil, ref = f })
		end
		for i, m in ipairs(L.moves) do
			local e = { key = led.key .. ":m" .. i, t = m.t, kind = m.kind, id = m.id, q = m.q, who = who, other = Short(m.to or m.from), ref = m }
			if m.kind == "goldOut" then
				e.debit = m.money
			elseif m.kind == "goldIn" then
				e.credit = m.money
			end
			Add(e)
		end
	end
	sort(out, function(a, b)
		if a.t ~= b.t then
			return a.t > b.t
		end
		return a.key < b.key
	end)
	return out
end

-- the operation of a journal entry, in words
function Eco.JournalLabel(e)
	local k = KINDS[e.kind]
	local label = k and k[1] or e.kind
	if e.other then
		label = label .. " " .. e.other
	end
	return label
end

------------------------------------------------------------------------
-- What to review next (Overview): stock to look at, sales followed,
-- opportunities checked, a scan to refresh
------------------------------------------------------------------------

function Eco.ReviewActions(scope)
	local out, now = {}, time()
	local review = 0
	for _, row in ipairs(Eco.Inventory(scope)) do
		local st = row.stats
		local lot = st.oldest
		if lot and (now - lot.t > 72 * HOUR or (now - lot.t > 48 * HOUR and (lot.s48 or 0) / lot.q < 0.3)) then
			review = review + 1
		end
	end
	if review > 0 then
		out[#out + 1] = { kind = "stock", count = review, text = format("%d item%s in stock to review (3 days or more, or slow to sell)", review, review > 1 and "s" or ""), page = "business", view = "inventory", stamp = "review" }
	end
	local sales = #Eco.SalesList(scope, now - 7 * DAY)
	if sales > 0 then
		out[#out + 1] = { kind = "sales", count = sales, text = format("%d sale%s followed in the last 7 days", sales, sales > 1 and "s" or ""), page = "business", view = "sales", stamp = "sold" }
	end
	local verified = Eco.VerifiedOpportunities and Eco.VerifiedOpportunities() or 0
	if verified > 0 then
		out[#out + 1] = { kind = "opps", count = verified, text = format("%d verified opportunit%s to look at", verified, verified > 1 and "ies" or "y"), page = "gold", stamp = "verified" }
	end
	local _, r = DB()
	if not r.lastScan or now - r.lastScan > 6 * HOUR then
		out[#out + 1] = { kind = "scan", text = r.lastScan and format("Prices are %s old: scan the auction house again", (Eco.Ago(r.lastScan):gsub(" ago", ""))) or "No scan yet: open the auction house and press Scan", page = "market", stamp = "review" }
	end
	return out
end
