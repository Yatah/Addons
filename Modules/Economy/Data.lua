--[[
	WC3 Console - economy (auction house)
	  Data.lua      helpers, markets, saved data, price history, auctions
	  Scan.lua      what is read from the game: auction house scans, vendor
	                prices, recipes
	  Ledger.lua    your trades: purchases, sales, postings, expiries
	  Disenchant.lua  can an item be disenchanted (confirmed by the game,
	                forbidden, not known), who can do it
	  Analysis.lua  Deals, Trades, Market, Crafts, Enchant
	  Widgets.lua   list, dropdown, chart, number box
	  Views.lua     the columns and tooltips of the lists
	  Window.lua    the window, its tabs, the auction house buttons, /wc3c eco

	  - Scan button under the auction house (and in the window):
	      full scan  every auction (C_AuctionHouse.ReplicateItems), once per
	                 15 min for the whole account
	      quick scan the lowest price and the quantity of every item (the
	                 auction house browse list) while the full scan waits
	  - price database per market (region, realm, side of the auction house:
	    Alliance, Horde or Neutral): lowest price, listed quantity and the
	    price of every item (each full scan: the unit price where 20 % of
	    the listed quantity is reached); the stackables every 12 h (00-12 h,
	    12-24 h local time) with their listed quantity and the quantity near
	    the price, the gear every day; a period is the median of its scans;
	    28 days kept (14 for gear); indicators on daily values: medians of
	    3 / 14 days, quartiles, trend, spread, supply
	  - ledger (per character): your purchases, sales, expiries and
	    cancellations read from the auction house mails, your postings and
	    their deposits; stock by lot, sold within 48 h, profit
	  - recipes: saved each time a profession window is opened
	  - vendor prices of the reagents: saved at every merchant
	  - window (click on the gold of the info bar, /wc3c eco):
	      Market  which markets are active: price and supply trends, now
	              against the usual quantity at this hour, your sales,
	              confidence; filters watch / supply falling / my sales /
	              all; click: price and supply charts over 7, 14, 28 days
	      Deals   auctions below the vendor price (sure profit) and resale:
	              prudent price, max buy price, status and quantity to buy
	              from the history, your sales and your budget; filtered by
	              category of item (game class / subclass, exceptions by
	              item id) and by resale method (AH, vendor)
	      Crafts  cost of the reagents (auction house, vendor or crafted
	              themselves) against the sale price of the product
	      Enchant lots of gear to disenchant (classic tables: quality, item
	              level, armor or weapon): the mean of a disenchant and its
	              spread, how many of the cheapest auctions to buy for the
	              chance of a profit asked for (80 %), the shopping list;
	              only the items the game confirmed as disenchantable, that
	              an enchanter of yours can disenchant; estimates only while
	              the yield tables are not validated on this client
	      Trades  your stock, sales, results and what to do with the stock
	    placed next to the auction house, above the bags and the console
]]

local _, ns = ...
local floor, min, abs, format = math.floor, math.min, math.abs, string.format
local pairs, type, tonumber, tostring, select = pairs, type, tonumber, tostring, select
local sort = table.sort

local Eco = { scanButtons = {} }
ns.Economy = Eco

Eco.cut = 0.05 -- what the auction house keeps of a sale (15 % at a neutral one)
Eco.stamp = 0 -- changes with each scan (cached indicators)
Eco.PACK = 4096.0 -- book entry: unit price * PACK + quantity (a float: exact up to 2^53)
local PACK = Eco.PACK
local HISTORY_DAYS = 28
Eco.HISTORY_DAYS = HISTORY_DAYS

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant
local RequestItem = (C_Item and C_Item.RequestLoadItemDataByID) or function() end

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

local GI = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:1:0|t"
local SI = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:1:0|t"
local CI = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:1:0|t"

function Eco.Thousands(n)
	n = floor(n or 0)
	if _G.BreakUpLargeNumbers then
		return _G.BreakUpLargeNumbers(n)
	end
	return tostring(n)
end
local Thousands = Eco.Thousands

-- compact money: 12g 34s, 5s 06c, 7c (copper dropped above a gold)
function Eco.Money(c)
	if not c then
		return "|cff808080?|r"
	end
	local neg = c < 0
	c = floor(abs(c) + 0.5)
	local g, s, k = floor(c / 10000), floor(c / 100) % 100, c % 100
	local t
	if g > 0 then
		t = Thousands(g) .. GI .. format(" %02d", s) .. SI
	elseif s > 0 then
		t = s .. SI .. format(" %02d", k) .. CI
	else
		t = k .. CI
	end
	return (neg and "-" or "") .. t
end

function Eco.ProfitText(c)
	if not c then
		return Eco.Money(nil)
	end
	return (c >= 0 and "|cff20ff20" or "|cffff4040") .. Eco.Money(c) .. "|r"
end

-- local time: the days and the 12 h periods start at midnight and noon
-- here (the offset from UTC, summer time included, is checked every 10 min)
local offset, offsetAt = 0, -1e9
local function LocalTime()
	local now = time()
	if now - offsetAt > 600 then
		local l, u = date("*t", now), date("!*t", now)
		u.isdst = l.isdst
		offset, offsetAt = now - time(u), now
	end
	return now + offset
end

function Eco.Today()
	return floor(LocalTime() / 86400)
end
local Today = Eco.Today

function Eco.Period()
	return floor(LocalTime() / 43200)
end

-- the time (for date()) of the start of a period / of the middle of a day
function Eco.PeriodTime(p)
	return p * 43200 - offset
end

function Eco.DayTime(d)
	return d * 86400 + 43200 - offset
end

function Eco.Ago(t)
	if not t then
		return "never"
	end
	local d = time() - t
	if d < 90 then
		return "just now"
	elseif d < 3600 then
		return format("%d min ago", floor(d / 60))
	elseif d < 86400 then
		return format("%d h ago", floor(d / 3600))
	end
	return format("%d days ago", floor(d / 86400))
end

function Eco.QualityColor(q)
	local c = _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[q or 1]
	if c then
		return c.r, c.g, c.b
	end
	return 1, 1, 1
end

function Eco.Icon(id)
	local icon = id and select(5, GetItemInfoInstant(id))
	return icon or 134400
end

function Eco.LinkID(link)
	return link and tonumber(link:match("item:(%d+)"))
end
local LinkID = Eco.LinkID

-- random suffix ("of the Eagle"): its own prices
function Eco.LinkSuffix(link)
	local s = link and tonumber(link:match("item:%d+:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:([^:|]*)"))
	if s and s ~= 0 then
		return s
	end
end

-- the item id of a price key (id, or "id:suffix")
function Eco.BaseID(key)
	if type(key) == "number" then
		return key
	end
	return tonumber(tostring(key):match("^(%d+)"))
end

-- item infos (id or link), once they are in the client cache; a few load
-- requests per pass (a computation of the window), GET_ITEM_INFO_RECEIVED
-- refreshes it
local items, requests = {}, 0
function Eco.Item(ref)
	if not ref then
		return nil
	end
	local i = items[ref]
	if i then
		return i
	end
	local name, link, quality, level, _, _, _, stack, equipLoc, icon, sell, class, _, bind = GetItemInfo(ref)
	if not name then
		local id = type(ref) == "number" and ref or LinkID(ref)
		if id and requests < 400 then
			requests = requests + 1
			RequestItem(id)
		end
		return nil
	end
	i = {
		name = name, link = link, quality = quality or 1, level = level, equipLoc = equipLoc, icon = icon,
		sell = sell or 0, class = class, bind = bind, stack = stack or 1,
	}
	items[ref] = i
	return i
end
local Item = Eco.Item

function Eco.NewPass()
	requests = 0
	-- (the tooltips read to know what can be disenchanted: Disenchant.lua)
	if Eco.DENewPass then
		Eco.DENewPass()
	end
end

-- not known yet: asked to the server, known at a later pass
function Eco.RequestItem(id)
	RequestItem(id)
end

local gear = {}
function Eco.IsGear(id)
	local g = gear[id]
	if g == nil then
		local _, _, _, loc = GetItemInfoInstant(id)
		g = loc ~= nil and loc ~= "" and loc ~= "INVTYPE_NON_EQUIP" and loc ~= "INVTYPE_NON_EQUIP_IGNORE"
		gear[id] = g
	end
	return g
end

function Eco.AuctionHouseOpen()
	local f = _G.AuctionHouseFrame
	return (f and f:IsShown()) and true or false
end

------------------------------------------------------------------------
-- Saved data
--   WC3ConsoleDB.eco = { realms = { [market] = { items, scanId, lastScan,
--     lastMode, lastAuctions, lastItems } }, vendor = { [id] = unit price },
--     sell = { [id] = vendor sell price }, settings, enchanters, watch,
--     lastFull, pos }
--   item record: m lowest unit price, q listed quantity, n auctions,
--     t last seen, s scan id, l link (suffix), u (gear read without its
--     link: no resale deal); history: hp = { [period] = packed } for the
--     stackables (their scans of the period: sp, ds, dq, dn), h = { [day] =
--     price } for the gear (dd, ds); v price of the last full scan, qn
--     quantity near it, qs usual quantity per 4 h slot, qdev now / usual
--   WC3ConsoleCharDB.recipes = { [profession] = { [recipe] = { o = item,
--     n = made, r = { [reagent] = quantity } } } }
------------------------------------------------------------------------

-- Markets: each auction house has its own prices. A market is the region,
-- the realm (the first of its connected realms: they share it) and the
-- side of the auction house: Alliance, Horde, or Neutral (a goblin
-- auctioneer in Booty Bay, Gadgetzan, Everlook: 15 % cut). The market is
-- the one of the last auction house opened, else your faction's.
local NEUTRAL_ZONES = { [1434] = true, [1446] = true, [1452] = true } -- Stranglethorn, Tanaris, Winterspring
local market = {}
Eco.market = market

-- (C_AutoComplete first: on Forever the global GetAutoCompleteRealms is only
-- Blizzard's deprecation wrapper, which returns this same list: the key of
-- the market does not change)
local function ConnectedRealms()
	local fn = (C_AutoComplete and C_AutoComplete.GetAutoCompleteRealms) or _G.GetAutoCompleteRealms
	return fn and fn()
end

local function RealmName()
	local realms = ConnectedRealms()
	if type(realms) == "table" and #realms > 0 then
		local list = {}
		for i, name in ipairs(realms) do
			list[i] = name
		end
		sort(list)
		return list[1]
	end
	return (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName() or "?"
end

function Eco.MarketKey(faction)
	local region = (GetCurrentRegionName and GetCurrentRegionName()) or ""
	return region .. "-" .. RealmName() .. "-" .. faction
end

function Eco.SetMarket(faction)
	market.faction = faction
	market.key = Eco.MarketKey(faction)
	market.label = (GetRealmName() or "?") .. " - " .. faction
	Eco.cut = faction == "Neutral" and 0.15 or 0.05
end

-- the side of the auction house being opened
function Eco.AuctionFaction()
	local player = UnitFactionGroup("player") or "?"
	if not UnitExists("npc") then
		return player
	end
	local npc = UnitFactionGroup("npc")
	if npc == "Alliance" or npc == "Horde" then
		return npc
	end
	local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	for _ = 1, 4 do
		if not map then
			break
		end
		if NEUTRAL_ZONES[map] then
			return "Neutral"
		end
		local info = C_Map.GetMapInfo(map)
		map = info and info.parentMapID
	end
	return player
end

-- the settings and their defaults (the others, of older versions, dropped)
local SETTINGS = {
	-- Deals: net return wanted on the purchase price (%), trading budget in
	-- gold (0: your gold + your stock), failed posts to cover by the price,
	-- stackables only, risky deals shown, category, subcategory, resale
	-- method (all, ah, vendor)
	minReturn = 25, budget = 0, failures = 2, stackOnly = true, showRisky = false,
	dealCategory = "all", dealSub = "all", dealMethod = "all",
	-- Market: its filter; Crafts: profitable only, soulbound hidden
	marketFilter = "all", onlyProfit = false, hideBound = true,
	-- Enchant: the chance of a profit of a lot (%), the return of each item
	-- bought (%), the expected profit of a lot, the capital of a plan
	-- (copper, 0: no plan), every lot shown
	deChance = 80, deReturn = 20, deMinProfit = 1000, deCapital = 0, deAll = false,
	-- Synergy: gold (crafts to disenchant) or level (skill points), the
	-- crafter shown ("all" or "character|profession")
	synMode = "gold", synWho = "all",
	-- The Goblin Ledger: theme, size of the book, the page opened, whose
	-- fortune ("char": this character, "all": every character of this realm
	-- and side), the range of the gold history, Make Gold's method, My
	-- Business's view and journal filters, Market's filters
	retailLedgerVersion = 0, theme = "merchant", ledgerScale = 1, ledgerPage = "overview", ledgerScope = "char", historyRange = "7d",
	goldMethod = "resell", businessView = "inventory", journalPeriod = "30d", journalChar = "all", journalKind = "all",
	marketCategory = "all", marketFavorites = false,
}

-- The account's data and the current market's (made once, again when the
-- market changes)
local cacheE, cacheR, cacheKey
function Eco.DB()
	local e = ns.db.eco
	if e and e == cacheE and cacheKey == market.key then
		return cacheE, cacheR
	end
	if type(e) ~= "table" then
		e = {}
		ns.db.eco = e
	end
	e.realms = e.realms or {}
	e.vendor = e.vendor or {}
	e.sell = e.sell or {}
	e.settings = e.settings or {}
	e.enchanters = e.enchanters or {}
	e.crafters = e.crafters or {} -- the recipes of every character (Synergy)
	e.watch = e.watch or {} -- Market: your selection
	local st = e.settings
	for k, v in pairs(SETTINGS) do
		if type(v) == "number" then
			st[k] = tonumber(st[k]) or v
		elseif st[k] == nil then
			st[k] = v
		end
	end
	for k in pairs(st) do
		if SETTINGS[k] == nil then
			st[k] = nil
		end
	end
	if not market.key then
		Eco.SetMarket(UnitFactionGroup("player") or "?")
	end
	local r = e.realms[market.key]
	if not r then
		r = { items = {}, scanId = 0 }
		e.realms[market.key] = r
	end
	cacheE, cacheR, cacheKey = e, r, market.key
	return e, r
end
local DB = Eco.DB

-- (the market's data was erased)
function Eco.ResetDB()
	cacheE = nil
end

function Eco.MarketLabel()
	DB()
	return market.label
end

function Eco.Recipes()
	local cdb = ns.cdb
	cdb.recipes = cdb.recipes or {}
	return cdb.recipes
end

-- vendor sell price of an item (kept: known without its infos)
function Eco.SellPriceOf(id)
	local e = DB()
	local it = Item(id)
	if it then
		e.sell[id] = it.sell
		return it.sell
	end
	return e.sell[id]
end

------------------------------------------------------------------------
-- Price history
------------------------------------------------------------------------

-- value of a sorted list at q (0.25: first quartile, 0.5: median)
local function Quantile(sorted, q)
	local n = #sorted
	if n == 0 then
		return nil
	end
	local pos = 1 + (n - 1) * q
	local lo = floor(pos)
	local a, b = sorted[lo], sorted[min(n, lo + 1)]
	return a + (b - a) * (pos - lo)
end

function Eco.Median(list)
	local sorted = {}
	for k = 1, #list do
		sorted[k] = list[k]
	end
	sort(sorted)
	return Quantile(sorted, 0.5)
end
local Median = Eco.Median

-- the samples of a period (12 at most)
function Eco.Push(list, v)
	list[#list + 1] = v
	if #list > 12 then
		table.remove(list, 1)
	end
	return list
end

-- sorted values of the last n days
local function Window(h, today, n)
	local list = {}
	for d, v in pairs(h) do
		local age = today - d
		if age >= 0 and age < n then
			list[#list + 1] = v
		end
	end
	sort(list)
	return list
end

-- a 12 h period of a stackable in one number (53 bits): price (0:
-- unknown, quick scans only), listed quantity (QUNKNOWN: unknown), the
-- part of it near the price in % (127: unknown)
local P_PRICE, P_TOTAL, QUNKNOWN = 67108864.0, 1048576.0, 1048575
function Eco.PackP(price, total, near)
	local code = 127
	if near and total and total > 0 then
		code = min(100, floor(near / total * 100 + 0.5))
	elseif near then
		code = 0
	end
	local t = total and min(floor(total + 0.5), QUNKNOWN - 1) or QUNKNOWN
	return (min(floor((price or 0) + 0.5), P_PRICE - 1) * P_TOTAL + t) * 128.0 + code
end

-- price, listed quantity, quantity near the price
function Eco.UnpackP(v)
	local code = v % 128
	v = (v - code) / 128
	local total = v % P_TOTAL
	local price = (v - total) / P_TOTAL
	if total == QUNKNOWN then
		total = nil
	end
	return price > 0 and price or nil, total, (code ~= 127 and total) and total * code / 100 or nil
end
local UnpackP = Eco.UnpackP

-- daily values of an item: the gear keeps one price per day (h); the
-- stackables a price and a supply per 12 h (hp), a day is the median of
-- its periods
function Eco.Daily(rec)
	if not rec.hp then
		return rec.h or {}
	end
	local lists = {}
	for p, v in pairs(rec.hp) do
		local d = floor(p / 2)
		local l = lists[d]
		if not l then
			l = { {}, {}, {} }
			lists[d] = l
		end
		local price, total, near = UnpackP(v)
		if price then
			l[1][#l[1] + 1] = price
		end
		if total then
			l[2][#l[2] + 1] = total
		end
		if near then
			l[3][#l[3] + 1] = near
		end
	end
	local prices, totals, nears = {}, {}, {}
	for d, l in pairs(lists) do
		prices[d] = l[1][1] and Median(l[1])
		totals[d] = l[2][1] and Median(l[2])
		nears[d] = l[3][1] and Median(l[3])
	end
	return prices, totals, nears
end

-- indicators of an item, from its daily values (kept until the next scan
-- or the next day):
--   m3, m14, m28  medians of the prices of 3, 14, 28 days
--   q25_7         first quartile of 7 days (a low reference)
--   q25, q75      quartiles of 14 days
--   trend         m3 / m14 - 1 (a recent fall when below -10 %)
--   spread        (q75 - q25) / m14 (prices tight up to 15 %)
--   days          days of price history (28 at most)
--   supply        listed quantity, 3 days against 14 (nearSupply: the
--                 quantity near the price)
local indicators = setmetatable({}, { __mode = "k" })
function Eco.Indicators(rec)
	local c = indicators[rec]
	local today = Today()
	if c and c.stamp == Eco.stamp and c.today == today then
		return c
	end
	local prices, totals, nears = Eco.Daily(rec)
	local w3, w7, w14, w28 = Window(prices, today, 3), Window(prices, today, 7), Window(prices, today, 14), Window(prices, today, HISTORY_DAYS)
	c = {
		stamp = Eco.stamp, today = today,
		m3 = Quantile(w3, 0.5), m14 = Quantile(w14, 0.5), m28 = Quantile(w28, 0.5),
		q25_7 = Quantile(w7, 0.25), q25 = Quantile(w14, 0.25), q75 = Quantile(w14, 0.75),
		days = #w28, days14 = #w14,
	}
	if #w14 >= 5 and c.m14 > 0 then
		-- no price the last 3 days (gone from the auction house): no trend
		c.trend = c.m3 and c.m3 / c.m14 - 1
		c.spread = (c.q75 - c.q25) / c.m14
	end
	if totals then
		local t3, t14, n3, n14 = Window(totals, today, 3), Window(totals, today, 14), Window(nears, today, 3), Window(nears, today, 14)
		c.vol3, c.vol14, c.near3, c.near14 = Quantile(t3, 0.5), Quantile(t14, 0.5), Quantile(n3, 0.5), Quantile(n14, 0.5)
		c.volDays = #t14
		if #t14 >= 5 and c.vol14 > 0 then
			c.supply = c.vol3 / c.vol14 - 1
		end
		if #n14 >= 5 and #n3 > 0 and c.near14 > 0 then
			c.nearSupply = c.near3 / c.near14 - 1
		end
	end
	indicators[rec] = c
	return c
end

-- usual price (14 day median) and days of history
function Eco.MarketValue(rec)
	if not (rec and (rec.h or rec.hp)) then
		return nil, 0
	end
	local c = Eco.Indicators(rec)
	return c.m14, c.days
end

------------------------------------------------------------------------
-- Books (session): the sorted auctions of each item of the last scan
------------------------------------------------------------------------

local S = { state = "idle", books = {}, progress = 0 }
Eco.S = S

function Eco.Unpack(v)
	local c = v % PACK
	return (v - c) / PACK, c
end
local Unpack = Eco.Unpack

-- the auctions of a key: those of the last scan (its cheapest ones, saved,
-- once the game reloaded), else its lowest price
function Eco.Book(key, rec)
	return S.books[key] or rec.b or { rec.m * PACK + 1 }
end

-- lowest price, listed quantity, price of the scan: the unit price where
-- the cheapest 20 % of the listed quantity is reached (a few cheap units
-- do not become the price of the whole market)
function Eco.BookStats(book)
	local total = 0
	for j = 1, #book do
		total = total + book[j] % PACK
	end
	local target, qty, value = total * 0.2, 0, nil
	for j = 1, #book do
		local p, c = Unpack(book[j])
		qty = qty + c
		if qty >= target then
			value = p
			break
		end
	end
	local lowest = Unpack(book[1])
	return lowest, total, value or lowest
end

-- units listed near the price of the scan (up to 15 % above it): the real
-- competition, unlike stacks listed at any price
function Eco.NearQuantity(book, value)
	local limit, n = value * 1.15, 0
	for j = 1, #book do
		local p, c = Unpack(book[j])
		if p > limit then
			break
		end
		n = n + c
	end
	return n
end

-- mean unit price of the cheapest qty units
function Eco.BookUnit(key, qty)
	local book = S.books[key]
	if not book or qty <= 0 then
		return nil
	end
	local need, cost, last = qty, 0, nil
	for j = 1, #book do
		local p, c = Unpack(book[j])
		local take = min(c, need)
		cost, need, last = cost + p * take, need - take, p
		if need <= 0 then
			break
		end
	end
	if need > 0 then
		cost = cost + last * need
	end
	return cost / qty
end

-- sale price: the lowest price of the last scan (never above the market
-- value), else the market value when nobody sells it now; listed, market
-- value, days of history
function Eco.ProductPrice(id)
	local _, r = DB()
	local rec = r.items[id]
	if not rec then
		return nil, 0, nil, 0
	end
	local mv, days = Eco.MarketValue(rec)
	if rec.s == r.scanId then
		return mv and min(rec.m, mv) or rec.m, rec.q or 0, mv, days
	end
	return mv, 0, mv, days
end
