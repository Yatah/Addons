--[[
	WC3 Console - economy: the ledger, your own trades (per character),
	read from the auction house mails (won, successful, expired, cancelled),
	your postings and the merchants. An auction that disappears is not a
	sale: only these mails prove demand.
	  lots[id]  what you bought, oldest first: { t, q, c cost, l left, s48
	            units sold within 48 h of the purchase; v vendor purchase, a
	            traded since }; a sale takes the oldest units (their cost
	            is the cost of the sale)
	  sales     { t, id, q, g gross price, c cut, d deposit back, b cost of
	            the units taken from your lots, n those units; v vendor }
	  fails     { t, id, q, k kind, d deposit lost }
	  posts     { t, id, q, p price, d deposit }
	  moves     mail between characters: { t, kind ("out", "in", "goldOut",
	            "goldIn", "gave"), id, q, c known cost, u units of unknown
	            cost, money, to / from }: no sale, no profit
	  deposit[id] deposit per unit (posting or sale mail)
	  names, mails, buyback: what has been read already
	A lot of unknown cost (u: received without a known cost) has no c: it
	never counts as a cost of 0.

	Version 2 (2026-10-10): the ledger of every character is in the
	account's data (WC3ConsoleDB.eco.ledgers[character], k: its realm and
	side), so that the journal can show any character and a transfer by mail
	moves the stock with its cost. A character's ledger moves there at its
	first login with this version; its old copy (WC3ConsoleCharDB.ledger)
	stays as it was, frozen, for a rollback.
]]

local _, ns = ...
local Eco = ns.Economy
local floor, max, min, format = math.floor, math.max, math.min, string.format
local pairs, ipairs, tonumber, tostring = pairs, ipairs, tonumber, tostring
local sort = table.sort

local DB, Item, LinkID = Eco.DB, Eco.Item, Eco.LinkID
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo

local HOUR, DAY = 3600, 86400
Eco.HOUR, Eco.DAY = HOUR, DAY
local MAIL_DAYS = 30 -- an auction house mail lasts 30 days
local LEDGER_DAYS = 60

-- (each change: the statistics are computed again)
local version = 0
local function Changed()
	version = version + 1
end

local LEDGER_VERSION = 2

local function Copy(t)
	if type(t) ~= "table" then
		return t
	end
	local c = {}
	for k, v in pairs(t) do
		c[k] = Copy(v)
	end
	return c
end

local function Normalize(L)
	for _, field in ipairs({ "lots", "sales", "fails", "posts", "moves", "deposit", "names", "mails" }) do
		if type(L[field]) ~= "table" then
			L[field] = {}
		end
	end
end

-- (a ledger made for a character before its first login with version 2,
-- a transfer to it: its old ledger is added to it then)
local function Merge(L, old)
	for _, field in ipairs({ "sales", "fails", "posts" }) do
		for _, x in ipairs(old[field] or {}) do
			L[field][#L[field] + 1] = Copy(x)
		end
		sort(L[field], function(a, b)
			return (a.t or 0) < (b.t or 0)
		end)
	end
	for id, lots in pairs(old.lots or {}) do
		local into = L.lots[id] or {}
		L.lots[id] = into
		for _, lot in ipairs(lots) do
			into[#into + 1] = Copy(lot)
		end
		sort(into, function(a, b)
			return a.t < b.t
		end)
	end
	for _, field in ipairs({ "deposit", "names", "mails" }) do
		for k, v in pairs(old[field] or {}) do
			if L[field][k] == nil then
				L[field][k] = Copy(v)
			end
		end
	end
end

-- The ledger of a character (default: this one); nil for another character
-- never seen with version 2 (made: `make`, for a transfer to it)
local mineL, mineE -- (this character's, asked very often)
function Eco.Ledger(key, make)
	if key == nil and mineL and mineE == ns.db.eco then
		return mineL
	end
	local me = ns.CharKey()
	key = key or me
	local e = DB()
	if type(e.ledgers) ~= "table" then
		e.ledgers = {}
	end
	local L = e.ledgers[key]
	if type(L) ~= "table" then
		if key ~= me and not make then
			return nil
		end
		L = {}
		e.ledgers[key] = L
	end
	if not L.ok then
		Normalize(L)
		L.ok = true
	end
	if key == me then
		-- version 2: this character's old ledger, once (a copy: the old one stays)
		if L.v ~= LEDGER_VERSION or (ns.cdb.ledgerMoved ~= LEDGER_VERSION and type(ns.cdb.ledger) == "table") then
			if ns.cdb.ledgerMoved ~= LEDGER_VERSION and type(ns.cdb.ledger) == "table" then
				Merge(L, ns.cdb.ledger)
				L.migrated = time()
			end
			ns.cdb.ledgerMoved = LEDGER_VERSION
			L.v = LEDGER_VERSION
		end
		L.k = Eco.MarketKey(UnitFactionGroup("player") or "?")
		mineL, mineE = L, e
	end
	return L
end
local Ledger = Eco.Ledger

-- the characters of the account on this realm and side (the mail goes
-- between them): keys of their ledgers, gold, enchanters, crafters
function Eco.OwnCharacters()
	local e = DB()
	local mine, out, seen = Eco.MarketKey(UnitFactionGroup("player") or "?"), {}, {}
	local function Add(key, k)
		if type(key) == "string" and k == mine and not seen[key] then
			seen[key] = true
			out[#out + 1] = key
		end
	end
	Add(ns.CharKey(), mine)
	for _, list in ipairs({ e.ledgers or {}, e.fortune and e.fortune.chars or {}, e.enchanters or {}, e.crafters or {} }) do
		for key, v in pairs(list) do
			Add(key, type(v) == "table" and v.k)
		end
	end
	sort(out)
	return out
end

-- the ledgers of a scope ("all": every character of this realm and side,
-- else a character key): { key, who, L }
function Eco.Ledgers(scope)
	local out = {}
	for _, key in ipairs(Eco.OwnCharacters()) do
		if scope == nil or scope == "all" or scope == key then
			local L = Ledger(key)
			if L then
				out[#out + 1] = { key = key, who = key:match("^[^-]+") or key, L = L }
			end
		end
	end
	return out
end

-- one of your characters of this realm and side, from a name typed in a
-- mail ("Clovis", "Clovis-Realm"): its key, nil for someone else
local function Squash(s)
	return (s or ""):lower():gsub("[%s%-']", "")
end
function Eco.OwnCharacterNamed(name)
	if type(name) ~= "string" or name == "" then
		return nil
	end
	local who, realm = name:match("^([^%-]+)%-?(.*)$")
	realm = realm ~= "" and realm or GetRealmName()
	for _, key in ipairs(Eco.OwnCharacters()) do
		local kw, kr = key:match("^([^%-]+)%-(.*)$")
		if kw and Squash(kw) == Squash(who) and Squash(kr) == Squash(realm) then
			return key
		end
	end
end

-- deposit of one unit posted for 24 h: learned from your postings and sale
-- mails, else about 30 % of the vendor price (estimate)
function Eco.DepositPerUnit(id)
	local d = Ledger().deposit[id]
	if d then
		return d, true
	end
	return (Eco.SellPriceOf(id) or 0) * 0.3, false
end
local DepositPerUnit = Eco.DepositPerUnit

-- a sale takes the oldest units bought; only auction house sales tell the
-- demand (sold within 48 h), a vendor sale just empties the stock.
-- parts: what was taken, to put it back (buyback, this session only)
local function Consume(L, id, qty, t, vendor)
	local basis, based, parts = 0, 0, {}
	for _, lot in ipairs(L.lots[id] or {}) do
		if qty <= 0 then
			break
		end
		if lot.l > 0 then
			local take = min(lot.l, qty)
			lot.l, qty = lot.l - take, qty - take
			-- (a lot of unknown cost: these units have no basis, never 0)
			if lot.c then
				basis, based = basis + lot.c / lot.q * take, based + take
			end
			local s48 = 0
			if not vendor and t - lot.t <= 48 * HOUR then
				s48 = take
				lot.s48 = (lot.s48 or 0) + take
			end
			parts[#parts + 1] = { lot, take, s48 }
		end
	end
	return basis, based, parts
end

-- vendor purchases (v) become stock once traded (a): posted or sold at
-- the auction house; reagents bought to craft stay out of the stock
local function Activate(L, id)
	for _, lot in ipairs(L.lots[id] or {}) do
		if lot.v then
			lot.a = true
		end
	end
end

local function AddLot(L, id, lot)
	local lots = L.lots[id] or {}
	L.lots[id] = lots
	lots[#lots + 1] = lot
	sort(lots, function(a, b)
		return a.t < b.t
	end)
end

local function Record(L, kind, id, qty, t, amount, cut, deposit)
	if kind == "bought" then
		AddLot(L, id, { t = t, q = qty, c = amount or 0, l = qty, s48 = 0 })
	elseif kind == "sold" then
		Activate(L, id)
		local basis, based = Consume(L, id, qty, t)
		L.sales[#L.sales + 1] = { t = t, id = id, q = qty, g = amount or 0, c = cut or 0, d = deposit, b = basis, n = based }
		if deposit and deposit > 0 then
			L.deposit[id] = deposit / qty
		end
	else
		L.fails[#L.fails + 1] = { t = t, id = id, q = qty, k = kind, d = DepositPerUnit(id) * qty }
	end
end

-- used or sold elsewhere: the stock of an item forgotten (a character's:
-- key, default this one)
function Eco.ForgetStock(id, key)
	local L = Ledger(key) or Ledger()
	for _, lot in ipairs(L.lots[id] or {}) do
		lot.l = 0
	end
	Changed()
	Eco.Refresh()
end

------------------------------------------------------------------------
-- Merchants: what you sell appears in the buyback list (right click, drag
-- or "sell junk" alike): a new entry is a sale, an entry gone while the
-- list gets shorter is a buyback. Purchases: BuyMerchantItem, confirmed
-- by the gold that leaves.
------------------------------------------------------------------------

local undo = setmetatable({}, { __mode = "k" }) -- vendor sale -> parts (session)

local function BuybackList()
	local list = {}
	for i = 1, GetNumBuybackItems() do
		local _, _, price, quantity = GetBuybackItemInfo(i)
		local id = LinkID(GetBuybackItemLink(i))
		if id and price then
			list[#list + 1] = format("%d:%d:%d", id, quantity or 1, price)
		end
	end
	return list
end

local function VendorSale(L, id, qty, price)
	local t = time()
	local basis, based, parts = Consume(L, id, qty, t, true)
	local sale = { t = t, id = id, q = qty, g = price, c = 0, b = basis, n = based, v = true }
	L.sales[#L.sales + 1] = sale
	undo[sale] = parts
end

local function Buyback(L, id, qty, price)
	for i = #L.sales, 1, -1 do
		local sale = L.sales[i]
		if sale.v and sale.id == id and sale.q == qty and sale.g == price and undo[sale] then
			for _, part in ipairs(undo[sale]) do
				local lot = part[1]
				lot.l, lot.s48 = lot.l + part[2], (lot.s48 or 0) - part[3]
			end
			undo[sale] = nil
			table.remove(L.sales, i)
			return
		end
	end
end

local function CheckBuyback()
	local L = Ledger()
	local old, new = L.buyback or {}, BuybackList()
	local left = {}
	for _, sig in ipairs(old) do
		left[sig] = (left[sig] or 0) + 1
	end
	local added = {}
	for _, sig in ipairs(new) do
		if (left[sig] or 0) > 0 then
			left[sig] = left[sig] - 1
		else
			added[#added + 1] = sig
		end
	end
	-- shorter list: bought back (a full list only pushes its oldest out)
	if #new < #old then
		for sig, n in pairs(left) do
			local id, qty, price = sig:match("^(%d+):(%d+):(%d+)$")
			for _ = 1, n do
				Buyback(L, tonumber(id), tonumber(qty), tonumber(price))
			end
		end
	end
	for _, sig in ipairs(added) do
		local id, qty, price = sig:match("^(%d+):(%d+):(%d+)$")
		VendorSale(L, tonumber(id), tonumber(qty), tonumber(price))
	end
	L.buyback = new
	if #added > 0 or #new < #old then
		Changed()
		Eco.Refresh()
	end
end

local merchantOpen, buybackPending = false, false
local function CheckBuybackSoon()
	if not merchantOpen or buybackPending then
		return
	end
	buybackPending = true
	C_Timer.After(0.3, function()
		buybackPending = false
		ns.Try("economy vendor sale", CheckBuyback)
	end)
end
ns.On("MERCHANT_SHOW", function()
	merchantOpen = true
	CheckBuybackSoon()
end)
ns.On("MERCHANT_CLOSED", function()
	merchantOpen = false
end)
ns.On("MERCHANT_UPDATE", CheckBuybackSoon)
ns.On("BAG_UPDATE_DELAYED", CheckBuybackSoon)

-- purchases waiting for their gold: { id, q, cost, t }
local buys, buyMoney = {}, nil
local function OnBuy(index, quantity)
	local id = GetMerchantItemID and GetMerchantItemID(index) or LinkID(GetMerchantItemLink(index))
	if not id then
		return
	end
	local price, stack
	if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
		local info = C_MerchantFrame.GetItemInfo(index)
		price, stack = info and info.price, info and info.stackCount
	else
		local _
		_, _, price, stack = GetMerchantItemInfo(index)
	end
	if not price or price <= 0 then
		return -- (paid with something else than gold)
	end
	stack = max(1, stack or 1)
	local units = quantity or stack
	if #buys == 0 then
		buyMoney = GetMoney()
	end
	buys[#buys + 1] = { id = id, q = units, cost = price * units / stack, t = time() }
end
hooksecurefunc("BuyMerchantItem", function(index, quantity)
	ns.Try("economy vendor buy", OnBuy, index, quantity)
end)

local function ConfirmBuys()
	if #buys == 0 then
		return
	end
	local L = Ledger()
	local spent = buyMoney - GetMoney()
	while buys[1] and spent >= buys[1].cost - 1 do
		local b = table.remove(buys, 1)
		spent, buyMoney = spent - b.cost, buyMoney - b.cost
		local it = Item(b.id)
		if it then
			L.names[it.name] = b.id
		end
		AddLot(L, b.id, { t = b.t, q = b.q, c = b.cost, l = b.q, s48 = 0, v = true })
		Changed()
	end
	-- a purchase without gold after 5 s never happened
	local now = time()
	for i = #buys, 1, -1 do
		if now - buys[i].t > 5 then
			table.remove(buys, i)
		end
	end
	if #buys == 0 then
		buyMoney = nil
	end
end

------------------------------------------------------------------------
-- Auction house mails
------------------------------------------------------------------------

local function SubjectPattern(fmt)
	local p = fmt:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0"):gsub("%%s", "(.+)")
	return "^" .. p .. "$"
end

local function NameToID(L, name)
	if not name then
		return nil
	end
	local id = L.names[name]
	if not id then
		local _, link = GetItemInfo(name)
		id = LinkID(link)
		if id then
			L.names[name] = id
		end
	end
	return id
end

-- the same mail is read at every visit: its signature and its expiry
-- (stable to the minute) tell it apart; identical mails are counted
local function Seen(L, sig, expiry, occurrence)
	local hour = floor(expiry / HOUR)
	for h = hour - 1, hour + 1 do
		if L.mails[sig .. "#" .. occurrence .. "@" .. h] then
			return true
		end
	end
	L.mails[sig .. "#" .. occurrence .. "@" .. hour] = floor(expiry)
	return false
end

local function ReadInbox()
	local L = Ledger()
	local now = time()
	local expired = SubjectPattern(_G.AUCTION_EXPIRED_MAIL_SUBJECT or "Auction expired: %s")
	local cancelled = SubjectPattern(_G.AUCTION_REMOVED_MAIL_SUBJECT or "Auction cancelled: %s")
	local mails = {}
	for i = 1, GetInboxNumItems() do
		local _, _, _, subject, money, _, daysLeft, itemCount = GetInboxHeaderInfo(i)
		if subject and daysLeft then
			local kind, name, qty, amount, cut, deposit, id
			local invoice, itemName, _, bid, buyout, dep, consignment, _, _, _, count = GetInboxInvoiceInfo(i)
			if invoice == "seller" or invoice == "buyer" then
				kind = invoice == "seller" and "sold" or "bought"
				name, qty, amount = itemName, count, (bid and bid > 0) and bid or buyout
				if kind == "sold" then
					cut, deposit = consignment, dep
				end
			else
				name = subject:match(expired)
				kind = name and "expired"
				if not name then
					name = subject:match(cancelled)
					kind = name and "cancelled"
				end
			end
			if kind then
				if kind ~= "sold" and (itemCount or 0) > 0 then
					local _, attID, _, attCount = GetInboxItem(i, 1)
					id = attID
					if not (qty and qty > 0) then
						qty = attCount
					end
				end
				id = id or NameToID(L, name)
				if id then
					if name then
						L.names[name] = id
					end
					mails[#mails + 1] = {
						kind = kind, id = id, qty = (qty and qty > 0) and qty or 1, amount = amount, cut = cut, deposit = deposit,
						expiry = now + daysLeft * DAY, sig = format("%s|%s|%d|%d", kind, tostring(name), money or 0, amount or 0),
					}
				end
			end
		end
	end
	-- purchases first: a sale in the same visit takes from them
	sort(mails, function(a, b)
		if (a.kind == "bought") ~= (b.kind == "bought") then
			return a.kind == "bought"
		end
		return a.expiry < b.expiry
	end)
	local occurrences, added = {}, 0
	for _, m in ipairs(mails) do
		local sig = m.sig .. "|" .. m.qty
		occurrences[sig] = (occurrences[sig] or 0) + 1
		if not Seen(L, sig, m.expiry, occurrences[sig]) then
			Record(L, m.kind, m.id, m.qty, min(now, m.expiry - MAIL_DAYS * DAY), m.amount, m.cut, m.deposit)
			added = added + 1
		end
	end
	-- forget what is too old
	local old = now - LEDGER_DAYS * DAY
	for _, list in ipairs({ L.sales, L.fails, L.posts, L.moves }) do
		for i = #list, 1, -1 do
			if list[i].t < old then
				table.remove(list, i)
			end
		end
	end
	for id, lots in pairs(L.lots) do
		for i = #lots, 1, -1 do
			if lots[i].l <= 0 and lots[i].t < old then
				table.remove(lots, i)
			end
		end
		if #lots == 0 then
			L.lots[id] = nil
		end
	end
	for sig, expiry in pairs(L.mails) do
		if expiry < now - DAY then
			L.mails[sig] = nil
		end
	end
	Changed()
	if added > 0 then
		Eco.Refresh()
	end
end

local inboxPending = false
local function ReadInboxSoon()
	if inboxPending then
		return
	end
	inboxPending = true
	C_Timer.After(0.5, function()
		inboxPending = false
		ns.Try("economy mail", ReadInbox)
	end)
end
ns.On("MAIL_INBOX_UPDATE", ReadInboxSoon)
ns.On("MAIL_SHOW", ReadInboxSoon)

------------------------------------------------------------------------
-- Postings: the deposit is the gold that leaves your bags just after
------------------------------------------------------------------------

local pendingPost
local function OnPost(location, qty, price)
	local id = location and C_Item and C_Item.GetItemID and C_Item.GetItemID(location)
	if not id then
		return
	end
	local L = Ledger()
	local it = Item(id)
	if it then
		L.names[it.name] = id
	end
	Activate(L, id)
	local post = { t = time(), id = id, q = qty or 1, p = price }
	L.posts[#L.posts + 1] = post
	pendingPost = { post = post, money = GetMoney() }
	Changed()
end
if C_AuctionHouse and C_AuctionHouse.PostCommodity then
	hooksecurefunc(C_AuctionHouse, "PostCommodity", function(item, _, quantity, unitPrice)
		ns.Try("economy post", OnPost, item, quantity, unitPrice)
	end)
end
if C_AuctionHouse and C_AuctionHouse.PostItem then
	hooksecurefunc(C_AuctionHouse, "PostItem", function(item, _, quantity, _, buyout)
		ns.Try("economy post", OnPost, item, quantity, buyout)
	end)
end

local function PostDeposit()
	local p = pendingPost
	pendingPost = nil
	if p and time() - p.post.t <= 15 then
		local spent = p.money - GetMoney()
		if spent > 0 then
			p.post.d = spent
			Ledger().deposit[p.post.id] = spent / p.post.q
			Changed()
		end
	end
end

-- the gold that moves: a vendor purchase paid, a deposit, a vendor sale
ns.On("PLAYER_MONEY", function()
	ns.Try("economy vendor buy", ConfirmBuys)
	ns.Try("economy post", PostDeposit)
	CheckBuybackSoon()
end)

------------------------------------------------------------------------
-- Mail between characters. Sent to one of your characters (same realm and
-- side), items are a transfer: their units leave this ledger with their
-- cost (oldest first) and enter the other one's, no sale, no profit; units
-- without a known cost stay of unknown cost there. Sent to someone else,
-- they leave the stock (a gift or a private trade: no profit known). Gold
-- sent is written too, never as income or profit. Only a mail really sent
-- counts (MAIL_SEND_SUCCESS), never an attempt.
------------------------------------------------------------------------

-- take qty units out of the lots, oldest first: { t, take, unit cost or nil }
-- and the units no lot held
local function Take(L, id, qty)
	local parts = {}
	for _, lot in ipairs(L.lots[id] or {}) do
		if qty <= 0 then
			break
		end
		if lot.l > 0 then
			local take = min(lot.l, qty)
			lot.l, qty = lot.l - take, qty - take
			parts[#parts + 1] = { t = lot.t, take = take, unit = lot.c and lot.c / lot.q or nil, v = lot.v, a = lot.a }
		end
	end
	return parts, qty
end

local outgoing
local function OnSendMail(to)
	local items = {}
	for i = 1, (_G.ATTACHMENTS_MAX_SEND or 12) do
		local _, itemID, _, count = GetSendMailItem(i)
		local id = (type(itemID) == "number" and itemID) or LinkID(GetSendMailItemLink and GetSendMailItemLink(i))
		if id and count and count > 0 then
			items[#items + 1] = { id = id, q = count }
		end
	end
	local money = GetSendMailMoney and GetSendMailMoney() or 0
	outgoing = { to = to, items = items, money = money or 0, t = time() }
end
if _G.SendMail then
	hooksecurefunc("SendMail", function(to)
		ns.Try("economy mail sent", OnSendMail, to)
	end)
end

local function Sent()
	local out = outgoing
	outgoing = nil
	if not out or time() - out.t > 30 then
		return
	end
	local L, me = Ledger(), ns.CharKey()
	local own = Eco.OwnCharacterNamed(out.to)
	local T = own and own ~= me and Ledger(own, true) or nil
	if T and not T.k then
		T.k = L.k
	end
	local now = time()
	for _, item in ipairs(out.items) do
		local parts, left = Take(L, item.id, item.q)
		local known, unknown = 0, left
		for _, p in ipairs(parts) do
			if p.unit then
				known = known + p.unit * p.take
			else
				unknown = unknown + p.take
			end
			if T then
				AddLot(T, item.id, { t = p.t, q = p.take, c = p.unit and p.unit * p.take or nil, l = p.take, s48 = 0, v = p.v, a = p.a, x = me })
			end
		end
		if T and left > 0 then
			AddLot(T, item.id, { t = now, q = left, l = left, s48 = 0, a = true, x = me })
		end
		L.moves[#L.moves + 1] = { t = now, kind = T and "out" or "gave", id = item.id, q = item.q, c = known, u = unknown, to = own or out.to }
		if T then
			T.moves[#T.moves + 1] = { t = now, kind = "in", id = item.id, q = item.q, c = known, u = unknown, from = me }
		end
	end
	if out.money > 0 then
		L.moves[#L.moves + 1] = { t = now, kind = "goldOut", money = out.money, to = own or out.to }
		if T then
			T.moves[#T.moves + 1] = { t = now, kind = "goldIn", money = out.money, from = me }
		end
	end
	Changed()
	Eco.Refresh()
end
ns.On("MAIL_SEND_SUCCESS", function()
	ns.Try("economy mail sent", Sent)
end)
ns.On("MAIL_FAILED", function()
	outgoing = nil
end)

------------------------------------------------------------------------
-- Per item: stock, sales, sell-through within 48 h, profit (computed again
-- after a change of the ledger, else once a minute)
--   state: validated (70 % sold within 48 h, 2 lots at least), stop
--   (under 30 %), small (between); nil: nothing to judge yet
------------------------------------------------------------------------

-- (per ledger: L, default this character's; unknown: units of unknown cost
-- in stock, never in the costs)
local statsCache = setmetatable({}, { __mode = "k" })
function Eco.LedgerStats(L)
	L = L or Ledger()
	local now = time()
	local c = statsCache[L]
	if c and c.version == version and c.minute == floor(now / 60) then
		return c.stats
	end
	local stats = {}
	local function Of(id)
		local s = stats[id]
		if not s then
			s = {
				id = id, stock = 0, stockCost = 0, unknown = 0, bought = 0, boughtCost = 0, sold7 = 0, sold = 0, gross = 0,
				gross14 = 0, units14 = 0, lost = 0, lost7 = 0, profit = 0, profit7 = 0, evalQty = 0,
				evalSold = 0, evalLots = 0, posts = 0, posted = 0, vendorSold = 0, vendorGross = 0, tied = 0,
			}
			stats[id] = s
		end
		return s
	end
	for id, lots in pairs(L.lots) do
		for _, lot in ipairs(lots) do
			-- vendor purchases count once traded
			if not lot.v or lot.a then
				local s = Of(id)
				if lot.c then
					s.bought, s.boughtCost = s.bought + lot.q, s.boughtCost + lot.c
				end
				if lot.l > 0 then
					s.stock = s.stock + lot.l
					if lot.c then
						s.stockCost = s.stockCost + lot.c / lot.q * lot.l
					else
						s.unknown = s.unknown + lot.l
					end
					if not s.oldest or lot.t < s.oldest.t then
						s.oldest = lot
					end
				end
				if now - lot.t >= 48 * HOUR then
					s.evalLots = s.evalLots + 1
					s.evalQty, s.evalSold = s.evalQty + lot.q, s.evalSold + (lot.s48 or 0)
				end
			end
		end
	end
	-- the first posting kept: sales and failures after it end postings
	local firstPost = {}
	for _, post in ipairs(L.posts) do
		local s = Of(post.id)
		s.posts, s.posted = s.posts + 1, s.posted + post.q
		firstPost[post.id] = min(firstPost[post.id] or post.t, post.t)
	end
	for _, sale in ipairs(L.sales) do
		local s = Of(sale.id)
		local net = sale.g - sale.c
		if sale.v then
			s.vendorSold, s.vendorGross = s.vendorSold + sale.q, s.vendorGross + sale.g
		else
			s.sold, s.gross = s.sold + sale.q, s.gross + sale.g
			if now - sale.t <= 7 * DAY then
				s.sold7 = s.sold7 + sale.q
			end
			if now - sale.t <= 14 * DAY then
				s.gross14, s.units14 = s.gross14 + sale.g, s.units14 + sale.q
			end
			if firstPost[sale.id] and sale.t >= firstPost[sale.id] then
				s.posted = s.posted - sale.q
			end
		end
		if (sale.n or 0) > 0 then
			local p = net * sale.n / sale.q - sale.b
			s.profit = s.profit + p
			if now - sale.t <= 7 * DAY then
				s.profit7 = s.profit7 + p
			end
		end
	end
	for _, f in ipairs(L.fails) do
		local s = Of(f.id)
		local d = f.d or 0
		s.lost, s.profit = s.lost + d, s.profit - d
		if now - f.t <= 7 * DAY then
			s.lost7, s.profit7 = s.lost7 + d, s.profit7 - d
		end
		if s.oldest and f.t >= s.oldest.t then
			s.lostOnStock = (s.lostOnStock or 0) + d
		end
		if firstPost[f.id] and f.t >= firstPost[f.id] then
			s.posted = s.posted - f.q
		end
	end
	for id, s in pairs(stats) do
		-- units still on the auction house: their deposit is paid, returned
		-- if they sell, lost if not
		s.onAH = max(0, s.posted)
		s.tied = s.onAH * DepositPerUnit(id)
		s.velocity = s.sold7 / 7
		s.avgSale = s.units14 > 0 and s.gross14 / s.units14 or nil
		s.sellThrough = s.evalQty > 0 and s.evalSold / s.evalQty or nil
		if s.sellThrough then
			if s.sellThrough < 0.3 then
				s.state = "stop"
			elseif s.sellThrough >= 0.7 and s.evalLots >= 2 then
				s.state = "validated"
			else
				s.state = "small"
			end
		end
		-- deposits really lost per unit sold, once enough is sold
		s.observedF = s.sold >= 10 and s.lost / s.sold or nil
	end
	statsCache[L] = { stats = stats, version = version, minute = floor(now / 60) }
	return stats
end

-- gold for trading: the budget set, else your gold and your stock
function Eco.Budget(st, invested)
	if st.budget > 0 then
		return st.budget * 10000
	end
	return GetMoney() + invested
end
