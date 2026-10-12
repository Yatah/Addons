--[[
	WC3 Console - economy: what is read from the game
	  auction house  full scan (every auction, once per 15 min for the
	                 account) or quick scan (the lowest price and quantity of
	                 every item), saved as the price history of the market
	  merchants      vendor prices of what they sell for gold
	  professions    the recipes of each profession window opened
]]

local _, ns = ...
local Eco = ns.Economy
local floor, ceil, max, min, format = math.floor, math.ceil, math.max, math.min, string.format
local pairs, ipairs, next, type = pairs, ipairs, next, type
local sort = table.sort

local DB, S, PACK = Eco.DB, Eco.S, Eco.PACK
local Median, Push, PackP, IsGear, BaseID = Eco.Median, Eco.Push, Eco.PackP, Eco.IsGear, Eco.BaseID
local LinkID, LinkSuffix = Eco.LinkID, Eco.LinkSuffix

local FULL_COOLDOWN = 15 * 60
local FULL_TIMEOUT = 60 -- no answer: the full scan is on cooldown, quick scan instead
local BROWSE_TIMEOUT = 180
local GEAR_HISTORY_DAYS = 14
local FORGET_DAYS = 30
local READ_STEP = 4000 -- auctions read per frame
local SAVE_STEP = 800 -- items saved per frame
local KEEP, KEEP_ABOVE = 8, 3 -- auctions saved per item (full scan), up to 3 x its lowest price
local KEEP_FOR = 3600 -- quick scans keep them so long after their full scan

------------------------------------------------------------------------
-- Markets and scans
------------------------------------------------------------------------

-- forget the prices of the current market (a new server, a wipe...)
function Eco.Purge()
	local e = DB()
	e.realms[Eco.market.key] = nil
	Eco.ResetDB()
	S.books = {}
	S.deAuctions = nil
	Eco.stamp = Eco.stamp + 1
	Eco.Refresh()
end

-- the auction house opened decides the market (its side)
function Eco.OpenMarket()
	local faction = Eco.AuctionFaction()
	if faction ~= Eco.market.faction then
		Eco.SetMarket(faction)
		S.books = {} -- (the auctions of another market)
		S.deAuctions = nil
		Eco.stamp = Eco.stamp + 1
		ns.Print("market: |cffffffff" .. Eco.market.label .. "|r")
	end
end

-- a full scan now, else the seconds to wait
function Eco.CanFullScan()
	local e = DB()
	local wait = (e.lastFull or 0) + FULL_COOLDOWN - time()
	return wait <= 0 and C_AuctionHouse and C_AuctionHouse.ReplicateItems ~= nil, max(0, wait)
end

local function StopTimer()
	if S.timer then
		S.timer:Cancel()
		S.timer = nil
	end
end

local function Abort(text)
	StopTimer()
	S.state = "idle"
	if text then
		ns.Print(text)
	end
	Eco.UpdateStatus()
end

-- the next step of a long task on the next frame (a failure stops the scan)
local function Later(delay, fn)
	C_Timer.After(delay, function()
		if not ns.Try("economy scan", fn) then
			Abort()
		end
	end)
end

-- the cheap end of the auctions of an item, saved: the lots to disenchant
-- and the deals of a full scan stay known once the game reloaded (the
-- whole scan is too big to save)
local function Cheapest(book, lowest)
	local out = {}
	for j = 1, min(#book, KEEP) do
		local p = Eco.Unpack(book[j])
		if p > lowest * KEEP_ABOVE then
			break
		end
		out[j] = book[j]
	end
	return #out > 1 and out or nil
end

-- a quick scan sees the lowest price of an item only: the auctions saved by
-- the last full scan stay, none at that price or under (bought, gone, or
-- that very one), that price in front
local function Merge(saved, lowest)
	local out = { lowest * PACK + 1 }
	for j = 1, #saved do
		if Eco.Unpack(saved[j]) > lowest then
			out[#out + 1] = saved[j]
		end
	end
	return #out > 1 and out or nil
end

-- Save a scan: books = { [key] = { packed auctions } }, links (gear with
-- a random suffix), unsure (gear read without its link), qtys: listed
-- quantities of a quick scan. The history: the median of the scans of a
-- period (more scans do not weigh more); a quick scan only knows the
-- lowest price, it adds the listed quantity, not a price.
--   stackables  every 12 h: price, listed quantity, quantity near the price
--   gear        every day: price
local function Finish(books, links, unsure, mode, auctions, qtys, exact)
	local _, r = DB()
	r.scanId = (r.scanId or 0) + 1
	local id, now, day, period = r.scanId, time(), Eco.Today(), Eco.Period()
	local slot = floor((tonumber(date("%H")) or 0) / 4) -- (4 h slots of the usual quantity)
	local full = mode == "full"
	local list = r.items
	local keys = {}
	for key in pairs(books) do
		keys[#keys + 1] = key
	end
	S.state = "saving"
	local j = 0
	local function Step()
		for _ = 1, SAVE_STEP do
			j = j + 1
			local key = keys[j]
			if not key then
				break
			end
			local book = books[key]
			sort(book)
			local lowest, qty, value = Eco.BookStats(book)
			local rec = list[key]
			if not rec then
				rec = {}
				list[key] = rec
			end
			rec.m, rec.t, rec.s = lowest, now, id
			if qtys then
				rec.q, rec.n = qtys[key] or qty, nil
			else
				rec.q, rec.n = qty, #book
			end
			rec.l = links[key] or rec.l
			rec.u = (type(key) == "number" and unsure[key]) or nil
			if full then
				rec.b = Cheapest(book, lowest)
				rec.deAuctions = nil
				if exact and exact[key] then
					table.sort(exact[key],function(a,b)return a.buyout/a.quantity<b.buyout/b.quantity end)
					rec.deAuctions={}
					for index=1,min(KEEP,#exact[key]) do rec.deAuctions[index]=exact[key][index] end
				end
			elseif rec.b and now - (r.fullAt or 0) <= KEEP_FOR then
				rec.b = Merge(rec.b, lowest)
				books[key] = rec.b or book
			else
				rec.b = nil
			end
			if not IsGear(BaseID(key)) then
				if rec.sp ~= period then
					rec.sp, rec.ds, rec.dq, rec.dn = period, {}, {}, {}
				end
				if full then
					Push(rec.ds, value)
					rec.v = value
					rec.qn = Eco.NearQuantity(book, value)
					Push(rec.dn, rec.qn)
				end
				Push(rec.dq, rec.q)
				rec.hp = rec.hp or {}
				rec.hp[period] = PackP(rec.ds[1] and Median(rec.ds) or 0, Median(rec.dq), rec.dn[1] and Median(rec.dn))
				-- the usual quantity at this time of day
				rec.qs = rec.qs or {}
				local usual = rec.qs[slot]
				rec.qdev = (usual and usual > 0) and (rec.q / usual - 1) or nil
				rec.qs[slot] = usual and floor(usual * 0.7 + rec.q * 0.3 + 0.5) or rec.q
			elseif full then
				if rec.dd ~= day then
					rec.dd, rec.ds = day, {}
				end
				rec.h = rec.h or {}
				rec.h[day] = floor(Median(Push(rec.ds, value)) + 0.5)
				rec.v = value
			end
		end
		S.progress = min(1, j / max(1, #keys))
		Eco.UpdateStatus()
		if j < #keys then
			Later(0, Step)
			return
		end
		-- forget the old history (28 days for the stackables, 14 for the
		-- gear: its pieces are less comparable) and the items not seen for
		-- a month
		local oldTime = now - FORGET_DAYS * 86400
		local oldPeriod, oldDay = period - Eco.HISTORY_DAYS * 2, day - GEAR_HISTORY_DAYS
		for key, rec in pairs(list) do
			if rec.s ~= id then
				rec.b = nil
			end
			-- a followed stackable absent from this scan: nothing is listed
			if rec.hp and rec.s ~= id then
				if rec.sp ~= period then
					rec.sp, rec.ds, rec.dq, rec.dn = period, {}, {}, {}
				end
				Push(rec.dq, 0)
				if full then
					Push(rec.dn, 0)
				end
				rec.hp[period] = PackP(rec.ds[1] and Median(rec.ds) or 0, Median(rec.dq), rec.dn[1] and Median(rec.dn))
			end
			if (rec.t or 0) < oldTime then
				list[key] = nil
			else
				for p in pairs(rec.hp or {}) do
					if p <= oldPeriod then
						rec.hp[p] = nil
					end
				end
				for d in pairs(rec.h or {}) do
					if d <= oldDay then
						rec.h[d] = nil
					end
				end
			end
		end
		r.lastScan, r.lastMode, r.lastAuctions, r.lastItems = now, mode, auctions, #keys
		if full then
			r.fullAt = now
		end
		S.books = books
		S.deAuctions = exact
		Eco.stamp = Eco.stamp + 1
		S.state = "idle"
		local deals, crafts = #Eco.ComputeDeals(), 0
		for _, c in ipairs(Eco.ComputeCrafts()) do
			if c.profit and c.profit > 0 then
				crafts = crafts + 1
			end
		end
		local size = full and (Eco.Thousands(auctions) .. " auctions, " .. Eco.Thousands(#keys) .. " items") or (Eco.Thousands(#keys) .. " items")
		ns.Print(format("%s scan done: %s, |cff20ff20%d deals|r, |cff20ff20%d profitable crafts|r, |cff20ff20%d lots advised to disenchant|r.",
			mode, size, deals, crafts, select(2, Eco.ComputeEnchant())))
		Eco.UpdateStatus()
		Eco.Refresh()
	end
	Later(0, Step)
end

-- Full scan: every auction; the rows of gear whose link is not loaded yet
-- are read again a bit later (their random suffix is in the link)
local function ReadFull(total)
	local AH = C_AuctionHouse
	local books, links, unsure, later = {}, {}, {}, {}
	local exact={}
	local function Add(itemID, count, buyout, link, noLink)
		local key = itemID
		local suffix = LinkSuffix(link)
		if suffix then
			key = itemID .. ":" .. suffix
			links[key] = links[key] or link
		end
		if noLink then
			unsure[itemID] = true
		end
		local book = books[key]
		if not book then
			book = {}
			books[key] = book
		end
		book[#book + 1] = ceil(buyout / count) * PACK + min(count, PACK - 1)
		if IsGear(itemID) and link then
			exact[key]=exact[key] or {}
			exact[key][#exact[key]+1]={key=key,link=link,buyout=buyout,quantity=count}
		end
	end
	local function Row(index, final)
		local _, _, count, _, _, _, _, _, _, buyout, _, _, _, owner, _, _, itemID = AH.GetReplicateItemInfo(index)
		if not (itemID and buyout and buyout > 0 and count and count > 0) or owner then
			return
		end
		if IsGear(itemID) then
			local link = AH.GetReplicateItemLink(index)
			if not link and not final then
				later[#later + 1] = index
				return
			end
			Add(itemID, count, buyout, link, not link)
		else
			Add(itemID, count, buyout)
		end
	end
	local tries = 0
	local function Retry()
		if S.state ~= "reading" then
			return
		end
		tries = tries + 1
		local list = later
		later = {}
		for _, index in ipairs(list) do
			Row(index, tries >= 3)
		end
		if #later > 0 then
			Later(2, Retry)
		else
			Finish(books, links, unsure, "full", total, nil, exact)
		end
	end
	local i = 0
	local function Step()
		if S.state ~= "reading" then
			return
		end
		local last = min(total, i + READ_STEP) - 1
		for index = i, last do
			Row(index, false)
		end
		i = last + 1
		S.progress = i / total
		Eco.UpdateStatus()
		if i < total then
			Later(0, Step)
		elseif #later > 0 then
			Later(1, Retry)
		else
			Finish(books, links, unsure, "full", total, nil, exact)
		end
	end
	S.state = "reading"
	S.progress = 0
	Later(0, Step)
end

ns.On("REPLICATE_ITEM_LIST_UPDATE", function()
	if S.state ~= "waiting" then
		return
	end
	local total = C_AuctionHouse.GetNumReplicateItems()
	if not total or total <= 0 then
		return
	end
	StopTimer()
	DB().lastFull = time()
	ReadFull(total)
end)

-- a search in the auction house's own search bar
local function StartSearch(text)
	local ah = _G.AuctionHouseFrame
	local bar = ah and ah.SearchBar
	if not (bar and bar.SearchBox) then
		return false
	end
	local tab = _G.AuctionHouseFrameBuyTab
	if tab and tab.Click and not bar:IsVisible() then
		tab:Click()
	end
	bar.SearchBox:SetText(text)
	if bar.StartSearch then
		bar:StartSearch()
	elseif bar.SearchButton then
		bar.SearchButton:Click()
	else
		return false
	end
	return true
end

-- Quick scan: the browse list of an empty search (every item: lowest
-- price, quantity), page after page
local function ReadBrowse()
	StopTimer()
	local results = C_AuctionHouse.GetBrowseResults() or {}
	local books, qtys = {}, {}
	for _, res in ipairs(results) do
		local k = res.itemKey
		local price = res.minPrice
		if k and k.itemID and price and price > 0 and (k.battlePetSpeciesID or 0) == 0 then
			local key = k.itemID
			if (k.itemSuffix or 0) ~= 0 then
				key = k.itemID .. ":" .. k.itemSuffix
			end
			books[key] = { price * PACK + 1 }
			qtys[key] = res.totalQuantity
		end
	end
	if not next(books) then
		return Abort("quick scan: no result.")
	end
	Finish(books, {}, {}, "quick", #results, qtys)
end

local function QuickScan()
	if not (C_AuctionHouse and C_AuctionHouse.GetBrowseResults) then
		return Abort("quick scan not available on this client.")
	end
	S.state = "browse"
	S.browseRequestedCount = nil
	S.pages = 0
	if not StartSearch("") then
		return Abort("quick scan: auction house search bar not found.")
	end
	StopTimer()
	S.timer = C_Timer.NewTimer(BROWSE_TIMEOUT, function()
		if S.state == "browse" then
			ns.Try("economy scan", ReadBrowse)
		end
	end)
	Eco.UpdateStatus()
end

local browsePending=false
local function RequestBrowsePage()
 if S.state~="browse" or browsePending then return end
 local count=#(C_AuctionHouse.GetBrowseResults() or {})
 if S.browseRequestedCount==count then return end
 browsePending=true
 C_Timer.After(1,function()
  browsePending=false
  if S.state~="browse" or not Eco.AuctionHouseOpen() then return end
  if C_AuctionHouse.IsThrottledMessageSystemReady and not C_AuctionHouse.IsThrottledMessageSystemReady() then return end
  S.browseRequestedCount=count
  C_AuctionHouse.RequestMoreBrowseResults()
 end)
end
ns.On("AUCTION_HOUSE_THROTTLED_SYSTEM_READY",function()
 if S.state=="browse" and not C_AuctionHouse.HasFullBrowseResults() then RequestBrowsePage() end
end)
local function OnBrowse()
	if S.state ~= "browse" then
		return
	end
	if C_AuctionHouse.HasFullBrowseResults() then
		ReadBrowse()
	else
		S.pages = (S.pages or 0) + 1
		Eco.UpdateStatus()
		RequestBrowsePage()
	end
end
ns.On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", OnBrowse)
ns.On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", OnBrowse)

-- the full scan when it is allowed (it answers within a minute), else the
-- quick one
function Eco.Scan()
	if S.state ~= "idle" then
		return
	end
	if not Eco.AuctionHouseOpen() then
		ns.Print("open the auction house to scan it.")
		return
	end
	if not Eco.CanFullScan() then
		QuickScan()
		return
	end
	S.state = "waiting"
	if not pcall(C_AuctionHouse.ReplicateItems) then
		S.state = "idle"
		QuickScan()
		return
	end
	StopTimer()
	S.timer = C_Timer.NewTimer(FULL_TIMEOUT, function()
		if S.state == "waiting" then
			S.state = "idle"
			ns.Print("no answer to the full scan (cooldown of 15 min?): quick scan instead.")
			QuickScan()
		end
	end)
	Eco.UpdateStatus()
end

ns.On("AUCTION_HOUSE_CLOSED", function()
	if S.state == "waiting" or S.state == "browse" or S.state == "reading" then
		Abort("auction house closed: scan stopped.")
	end
	Eco.UpdateStatus()
end)

-- an item in the auction house (click in the lists)
function Eco.Search(name)
	if not name then
		return
	end
	if not Eco.AuctionHouseOpen() then
		ns.Print("open the auction house to search |cffffffff" .. name .. "|r.")
		return
	end
	if S.state ~= "idle" then
		ns.Print("wait for the end of the scan.")
		return
	end
	StartSearch('"' .. name .. '"')
end

------------------------------------------------------------------------
-- Recipes (profession window) and vendor prices (merchant)
------------------------------------------------------------------------

-- A recipe: o its product, n how many it makes, r its reagents (id ->
-- quantity), d its colour at the rank of the window (0 orange, 1 yellow,
-- 2 green, 3 grey), u its skill points when more than 1. Every
-- character's are kept for the account too, with the rank of its
-- profession (Synergy: a crafter and an enchanter can be two characters)
local DIFFICULTY = { optimal = 0, medium = 1, easy = 2, trivial = 3 }

local function SaveCrafter(name, list, rank, maxRank)
	local e = DB()
	local key = ns.CharKey()
	local c = e.crafters[key]
	if type(c) ~= "table" then
		c = {}
		e.crafters[key] = c
	end
	c.k = Eco.MarketKey(UnitFactionGroup("player") or "?")
	c.p = type(c.p) == "table" and c.p or {}
	c.p[name] = { r = rank, m = maxRank, t = time(), list = list }
end

local function Difficulty(info)
	local d, RD = info.relativeDifficulty, Enum and Enum.TradeskillRelativeDifficulty
	if d ~= nil and RD then
		return (d == RD.Optimal and 0) or (d == RD.Medium and 1) or (d == RD.Easy and 2) or (d == RD.Trivial and 3) or nil
	elseif type(d) == "number" then
		return d
	end
	return DIFFICULTY[info.difficulty]
end

-- the modern profession window: its learned recipes, their basic reagents
local function SaveModernRecipes()
	local T = C_TradeSkillUI
	if (T.IsTradeSkillLinked and T.IsTradeSkillLinked()) or (T.IsTradeSkillGuild and T.IsTradeSkillGuild())
		or (T.IsNPCCrafting and T.IsNPCCrafting()) then
		return
	end
	if T.IsTradeSkillReady and not T.IsTradeSkillReady() then
		return
	end
	local prof = T.GetBaseProfessionInfo and T.GetBaseProfessionInfo()
	local name = prof and prof.professionName
	if (not name or name == "") and T.GetTradeSkillLine then
		name = select(2, T.GetTradeSkillLine())
	end
	if not name or name == "" then
		return
	end
	local rank, maxRank = prof and prof.skillLevel, prof and prof.maxSkillLevel
	if not rank and T.GetTradeSkillLine then
		rank, maxRank = select(3, T.GetTradeSkillLine())
	end
	local basic = (Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic) or 1
	local list, count = {}, 0
	for _, rid in ipairs(T.GetAllRecipeIDs() or {}) do
		local info = T.GetRecipeInfo(rid)
		local sch = info and info.learned and T.GetRecipeSchematic(rid, false)
		if sch and sch.outputItemID then
			local r, ok = {}, true
			for _, slot in ipairs(sch.reagentSlotSchematics or {}) do
				if slot.reagentType == basic and slot.required ~= false then
					local rg = slot.reagents and slot.reagents[1]
					local id = rg and (rg.itemID or (rg.reagent and rg.reagent.itemID))
					if id then
						r[id] = (r[id] or 0) + (slot.quantityRequired or 1)
					else
						ok = false -- (a currency...)
					end
				end
			end
			if ok and next(r) then
				local made = ((sch.quantityMin or 1) + (sch.quantityMax or sch.quantityMin or 1)) / 2
				local ups = info.numSkillUps
				list[rid] = { o = sch.outputItemID, n = max(1, made), r = r, d = Difficulty(info), u = (type(ups) == "number" and ups > 1) and ups or nil }
				count = count + 1
			end
		end
	end
	if count > 0 then
		Eco.Recipes()[name] = list
		SaveCrafter(name, list, tonumber(rank), tonumber(maxRank))
	end
end

-- the classic profession window
local function SaveLegacyRecipes()
	local name, rank, maxRank = GetTradeSkillLine()
	if not name or name == "" or name == "UNKNOWN" then
		return
	end
	if IsTradeSkillLinked and IsTradeSkillLinked() then
		return
	end
	local list, count = {}, 0
	for i = 1, GetNumTradeSkills() do
		local _, kind = GetTradeSkillInfo(i)
		local out = kind ~= "header" and kind ~= "subheader" and LinkID(GetTradeSkillItemLink(i))
		if out then
			local r, ok = {}, true
			for j = 1, GetTradeSkillNumReagents(i) do
				local _, _, qty = GetTradeSkillReagentInfo(i, j)
				local id = LinkID(GetTradeSkillReagentItemLink(i, j))
				if id and qty then
					r[id] = (r[id] or 0) + qty
				else
					ok = false
				end
			end
			if ok and next(r) then
				local lo, hi = GetTradeSkillNumMade(i)
				list["i" .. out] = { o = out, n = max(1, ((lo or 1) + (hi or lo or 1)) / 2), r = r, d = DIFFICULTY[kind] }
				count = count + 1
			end
		end
	end
	if count > 0 then
		Eco.Recipes()[name] = list
		SaveCrafter(name, list, tonumber(rank), tonumber(maxRank))
	end
end

local recipesPending = false
local function SaveRecipesSoon()
	if recipesPending then
		return
	end
	recipesPending = true
	C_Timer.After(0.5, function()
		recipesPending = false
		if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetRecipeSchematic then
			ns.Try("economy recipes", SaveModernRecipes)
		elseif GetNumTradeSkills then
			ns.Try("economy recipes", SaveLegacyRecipes)
		end
		Eco.Refresh()
	end)
end
for _, event in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED" }) do
	ns.On(event, SaveRecipesSoon)
end

-- the price of one unit, unlimited stock, paid in gold only
local function SaveVendor()
	local e = DB()
	for i = 1, GetMerchantNumItems() do
		local price, stack, available, extended
		if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
			local t = C_MerchantFrame.GetItemInfo(i)
			if t then
				price, stack, available, extended = t.price, t.stackCount, t.numAvailable, t.hasExtendedCost
			end
		else
			local _
			_, _, price, stack, available, _, _, extended = GetMerchantItemInfo(i)
		end
		local id = GetMerchantItemID and GetMerchantItemID(i) or LinkID(GetMerchantItemLink(i))
		if id and price and price > 0 and not extended and available == -1 then
			e.vendor[id] = price / max(1, stack or 1)
		end
	end
end
for _, event in ipairs({ "MERCHANT_SHOW", "MERCHANT_UPDATE" }) do
	ns.On(event, function()
		ns.Try("economy vendor", SaveVendor)
	end)
end
