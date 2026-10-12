--[[
	WC3 Console - The Goblin Ledger, My Business: what you hold and what you
	did, for the fortune chosen at the top (this character or all of them).
	  Inventory  the stock followed: quantities, known cost (Unknown cost
	             otherwise, never 0), estimated value, age, what to do
	  Auctions   your postings and what the mails told of them
	  Sales      revenue, the cut, the cost of the units of known cost, the
	             realized result
	  Journal    a register of what was really seen (mails, merchants,
	             postings, mails sent): date, item, operation, character,
	             quantity, debit, credit, result; filters by period,
	             character and operation; a click: its details
	Across the book (wide tables). Figures: Fortune.lua, Ledger.lua.
]]

local _, ns = ...
local Eco = ns.Economy
local floor, max, min, format = math.floor, math.max, math.min, string.format
local ipairs, tostring = ipairs, tostring

local B, T = Eco.Book, Eco.Theme
local DB, Item, Icon = Eco.DB, Eco.Item, Eco.Icon
local HOUR, DAY = Eco.HOUR, Eco.DAY

local page = B.Register({
	key = "business", label = "My Business", icon = [[Interface\Icons\INV_Misc_Book_09]], order = 3,
	about = "Your stock, your auctions, your sales and the journal of every operation seen.",
})

local VIEWS = { { "inventory", "Inventory" }, { "auctions", "Auctions" }, { "sales", "Sales" }, { "journal", "Journal" } }

local function NameCell(d)
	local it = (d.link and Item(d.link)) or Item(d.id)
	if it then
		local r, g, b = Eco.QualityColor(it.quality)
		return it.name, r, g, b
	end
	if not d.id then
		return "Gold", 1, 0.82, 0
	end
	return "item " .. tostring(d.id), 0.6, 0.6, 0.6
end

local function NameSort(d)
	local text = NameCell(d)
	return text:lower()
end

local function IconCell(d)
	if not d.id then
		return [[Interface\Icons\INV_Misc_Coin_01]]
	end
	return Icon(d.id)
end

local function Age(sec)
	if not sec then
		return "-"
	elseif sec < HOUR then
		return format("%dm", floor(sec / 60))
	elseif sec < DAY then
		return format("%dh", floor(sec / HOUR))
	end
	return format("%dd", floor(sec / DAY))
end

local function When(t)
	return date("%m-%d %H:%M", t)
end

local function MoneyOr(c, unknown)
	if c == nil then
		return unknown or "-", 0.6, 0.6, 0.6
	end
	return B.Money(c)
end

local function ResultCell(c, unknownText)
	if c == nil then
		return unknownText or "-", 1, 0.75, 0.2
	end
	local col = c >= 0 and B.GREEN or B.RED
	return B.Signed(c), col[1], col[2], col[3]
end

------------------------------------------------------------------------
-- Columns
------------------------------------------------------------------------

local function Review(d)
	local st = d.stats
	local lot = st and st.oldest
	if not lot then
		return nil
	end
	local age = time() - lot.t
	if age > 7 * DAY then
		return "Sell it off"
	elseif age > 48 * HOUR and (lot.s48 or 0) / lot.q < 0.3 then
		return "Stop buying"
	elseif age > 72 * HOUR then
		return "Check the price"
	end
end

local COLUMNS = {
	inventory = {
		{ label = "Item", width = 0, icon = IconCell, text = NameCell, sort = NameSort, desc = false },
		{ label = "Holder", width = 74, text = function(d)
			return d.who
		end, sort = function(d)
			return d.who
		end, desc = false },
		{ label = "Qty", width = 44, align = "RIGHT", text = function(d)
			return tostring(d.qty)
		end, sort = function(d)
			return d.qty
		end },
		{ label = "Known Cost", width = 96, align = "RIGHT", text = function(d)
			if not d.cost then
				return "Unknown cost", 1, 0.75, 0.2
			end
			return B.Money(d.cost) .. (d.unknown > 0 and format(" (+%d ?)", d.unknown) or "")
		end, sort = function(d)
			return d.cost
		end, tip = "What the units cost when bought (or received from your characters with their cost). (+n ?): units of unknown cost besides." },
		{ label = "Unit Cost", width = 84, align = "RIGHT", text = function(d)
			return MoneyOr(d.unit, "Unknown cost")
		end, sort = function(d)
			return d.unit
		end },
		{ label = "Est. Value", width = 96, align = "RIGHT", text = function(d)
			if not d.value then
				return "Not enough data", 1, 0.75, 0.2
			end
			return B.Money(d.value)
		end, sort = function(d)
			return d.value
		end, tip = "At today's market price, after the cut: an estimate, not counted in the profit." },
		{ label = "Age", width = 44, align = "RIGHT", text = function(d)
			return Age(d.age)
		end, sort = function(d)
			return d.age
		end },
		{ label = "To Do", width = 104, text = function(d)
			local advice = Review(d)
			if advice then
				return advice, 1, 0.6, 0.2
			end
			return "OK", 0.6, 0.6, 0.6
		end, sort = function(d)
			return Review(d) or ""
		end },
	},
	auctions = {
		{ label = "Posted", width = 86, text = function(d)
			return When(d.t), 0.75, 0.75, 0.75
		end, sort = function(d)
			return d.t
		end },
		{ label = "Item", width = 0, icon = IconCell, text = NameCell, sort = NameSort, desc = false },
		{ label = "Holder", width = 74, text = function(d)
			return d.who
		end, sort = function(d)
			return d.who
		end, desc = false },
		{ label = "Qty", width = 40, align = "RIGHT", text = function(d)
			return tostring(d.q)
		end, sort = function(d)
			return d.q
		end },
		{ label = "Price", width = 90, align = "RIGHT", text = function(d)
			return MoneyOr(d.price)
		end, sort = function(d)
			return d.price
		end },
		{ label = "Deposit", width = 80, align = "RIGHT", text = function(d)
			return MoneyOr(d.deposit, "Not known")
		end, sort = function(d)
			return d.deposit
		end },
		{ label = "State", width = 90, text = function(d)
			local c = (d.state == "Sold" and B.GREEN) or ((d.state == "Expired" or d.state == "Cancelled") and B.RED) or B.AMBER
			return d.state, c[1], c[2], c[3]
		end, sort = function(d)
			return d.state
		end, tip = "From the mails read after the posting: Sold, Expired, Cancelled. Listed: posted less than 48 h ago, no mail yet. Not known: no mail read about it." },
	},
	sales = {
		{ label = "Date", width = 86, text = function(d)
			return When(d.t), 0.75, 0.75, 0.75
		end, sort = function(d)
			return d.t
		end },
		{ label = "Item", width = 0, icon = IconCell, text = NameCell, sort = NameSort, desc = false },
		{ label = "Seller", width = 70, text = function(d)
			return d.who .. (d.vendor and " (vendor)" or "")
		end, sort = function(d)
			return d.who
		end, desc = false },
		{ label = "Qty", width = 40, align = "RIGHT", text = function(d)
			return tostring(d.q)
		end, sort = function(d)
			return d.q
		end },
		{ label = "Revenue", width = 92, align = "RIGHT", text = function(d)
			return B.Money(d.revenue)
		end, sort = function(d)
			return d.revenue
		end, tip = "The price paid, less the auction house cut." },
		{ label = "Cut", width = 74, align = "RIGHT", text = function(d)
			return B.Money(d.cut)
		end, sort = function(d)
			return d.cut
		end },
		{ label = "Cost", width = 92, align = "RIGHT", text = function(d)
			if not d.cost then
				return "Unknown cost", 1, 0.75, 0.2
			end
			return B.Money(d.cost) .. (d.unknown > 0 and format(" (%d ?)", d.unknown) or "")
		end, sort = function(d)
			return d.cost
		end, tip = "The cost of the units of known cost sold. (n ?): units of unknown cost, left out of the result." },
		{ label = "Result", width = 96, align = "RIGHT", text = function(d)
			return ResultCell(d.result, "Unknown cost")
		end, sort = function(d)
			return d.result
		end },
	},
	journal = {
		{ label = "Date", width = 86, text = function(d)
			return When(d.t), 0.75, 0.75, 0.75
		end, sort = function(d)
			return d.t
		end },
		{ label = "Item", width = 0, icon = IconCell, text = NameCell, sort = NameSort, desc = false },
		{ label = "Operation", width = 132, text = function(d)
			return Eco.JournalLabel(d)
		end, sort = function(d)
			return d.kind
		end, desc = false },
		{ label = "Character", width = 74, text = function(d)
			return d.who
		end, sort = function(d)
			return d.who
		end, desc = false },
		{ label = "Qty", width = 40, align = "RIGHT", text = function(d)
			return d.q and tostring(d.q) or "-"
		end, sort = function(d)
			return d.q
		end },
		{ label = "Debit", width = 84, align = "RIGHT", text = function(d)
			if not d.debit then
				return "-", 0.6, 0.6, 0.6
			end
			return "-" .. B.Money(d.debit), 1, 0.35, 0.35
		end, sort = function(d)
			return d.debit
		end, tip = "Gold out for this character." },
		{ label = "Credit", width = 84, align = "RIGHT", text = function(d)
			if not d.credit then
				return "-", 0.6, 0.6, 0.6
			end
			return "+" .. B.Money(d.credit), 0.3, 1, 0.3
		end, sort = function(d)
			return d.credit
		end, tip = "Gold in for this character (a sale: the price less the cut, its deposit back)." },
		{ label = "Result", width = 92, align = "RIGHT", text = function(d)
			if d.kind == "sellAH" or d.kind == "sellVendor" then
				return ResultCell(d.result, "Unknown cost")
			end
			return ResultCell(d.result, "-")
		end, sort = function(d)
			return d.result
		end, tip = "Profit or loss when it can be computed. Transfers between your characters: never a result." },
	},
}

------------------------------------------------------------------------
-- Creation
------------------------------------------------------------------------

function page.Create(p)
	p.state = p.state or {}
	page.spread = true
	local S = p.S
	local title = B.Text(S, "title")
	title:SetPoint("TOPLEFT", 0, 0)
	title:SetText("My Business")
	p.views = {}
	local prev
	for _, v in ipairs(VIEWS) do
		local b = B.Button(S, v[2], 96, function()
			DB().settings.businessView = v[1]
			p.state.detail = nil
			Eco.Refresh()
		end)
		if prev then
			b:SetPoint("LEFT", prev, "RIGHT", 4, 0)
		else
			b:SetPoint("LEFT", title, "RIGHT", 18, 0)
		end
		b.view = v[1]
		p.views[#p.views + 1] = b
		prev = b
	end
	-- filters (journal, sales)
	p.period = B.Dropdown(S, 140)
	p.period:SetPoint("TOPLEFT", 0, -34)
	p.kind = B.Dropdown(S, 140)
	p.kind:SetPoint("LEFT", p.period, "RIGHT", 6, 0)
	p.char = B.Dropdown(S, 150)
	p.char:SetPoint("LEFT", p.kind, "RIGHT", 6, 0)
	B.Tip(p.char, "Character", "The same choice as \"whose fortune\" at the top: this character, all of them, or one.")
	p.note = B.Text(S, "muted")
	p.note:SetPoint("TOPLEFT",S,"TOPLEFT",0,-34)
	p.note:SetPoint("TOPRIGHT", S, "TOPRIGHT", 0, -42)
	p.lists = {}
	for _, v in ipairs(VIEWS) do
		local list = B.List(S, COLUMNS[v[1]], v[1] == "inventory" and 6 or 1, 28)
		list.frame:SetPoint("TOPLEFT", 0, -64)
		list.frame:SetPoint("BOTTOMRIGHT", 0, 0)
		list.frame:Hide()
		if v[1] == "journal" or v[1] == "sales" or v[1] == "auctions" then
			list.sortDesc = true
		end
		list.onEnter = function(owner, d)
			if d.id then
				GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
				pcall(GameTooltip.SetHyperlink, GameTooltip, d.link or ("item:" .. d.id))
				if v[1] == "inventory" then
					GameTooltip:AddLine("Click: search it at the auction house; shift + right click: forget this stock (used or sold elsewhere)", 0.5, 0.8, 1, true)
				else
					GameTooltip:AddLine("Click: its details", 0.5, 0.8, 1)
				end
				GameTooltip:Show()
			end
		end
		list.onClick = function(d, button)
			if v[1] == "inventory" then
				if button == "RightButton" and IsShiftKeyDown() then
					Eco.ForgetStock(d.id, d.char)
				elseif d.id then
					local it = Item(d.id)
					Eco.Search(it and it.name)
				end
				return
			end
			list.selected = d.key
			p.state.detail = d.key
			Eco.Refresh()
		end
		p.lists[v[1]] = list
	end
	-- the details of an entry, at the bottom
	local card = B.Card(S)
	card:SetPoint("BOTTOMLEFT", 0, 0)
	card:SetPoint("BOTTOMRIGHT", 0, 0)
	card:SetHeight(96)
	card:Hide()
	p.detail = card
	card.icon = card:CreateTexture(nil, "ARTWORK")
	card.icon:SetSize(30, 30)
	card.icon:SetPoint("TOPLEFT", 8, -8)
	card.title = B.Text(card, "heading")
	card.title:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 8, 0)
	card.title:SetPoint("TOPRIGHT", card, "TOPRIGHT", -166, -8)
	card.text = B.Text(card, "body")
	card.text:SetPoint("TOPLEFT", card.icon, "BOTTOMLEFT", 0, -6)
	card.text:SetPoint("BOTTOMRIGHT", -8, 6)
	card.text:SetWordWrap(true)
	card.text:SetJustifyV("TOP")
	card.close = B.Button(card, "Close", 70, function()
		p.state.detail = nil
		Eco.Refresh()
	end, 20)
	card.close:SetPoint("TOPRIGHT", -8, -8)
	card.search = B.Button(card, "Search", 70, function()
		local it = card.id and Item(card.id)
		Eco.Search(it and it.name)
	end, 20)
	card.search:SetPoint("RIGHT", card.close, "LEFT", -4, 0)
end

------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------

local function CharOptions()
	local options = { { value = "char", label = "This character" }, { value = "all", label = "All characters" } }
	for _, key in ipairs(Eco.OwnCharacters()) do
		options[#options + 1] = { value = key, label = key:match("^[^-]+") or key }
	end
	return options
end

-- the details of a journal / sale / auction entry
local function Detail(p, view, d)
	local card = p.detail
	local it = d.id and Item(d.id)
	card.id = d.id
	card.icon:SetTexture(IconCell(d))
	local lines = {}
	if view == "journal" then
		card.title:SetText(format("%s  -  %s", Eco.JournalLabel(d), it and it.name or (d.id and ("item " .. d.id) or "gold")))
		lines[#lines + 1] = format("%s, by %s%s.", date("%Y-%m-%d %H:%M", d.t), d.who, d.q and format(", %d unit%s", d.q, d.q == 1 and "" or "s") or "")
		local r = d.ref
		if d.kind == "sellAH" or d.kind == "sellVendor" then
			local revenue, known = Eco.SaleFigures(r)
			lines[#lines + 1] = format("Price %s, cut %s, revenue %s%s.", B.Money(r.g), B.Money(r.c or 0), B.Money(revenue), r.d and (", deposit back " .. B.Money(r.d)) or "")
			if known > 0 then
				lines[#lines + 1] = format("Cost of the %d unit%s of known cost: %s; result %s.", known, known == 1 and "" or "s", B.Money(r.b), B.Signed(d.result))
			end
			if known < r.q then
				lines[#lines + 1] = format("Unknown cost: %d unit%s not bought by this character (or before its ledger): left out of the result, never counted as free.", r.q - known, r.q - known == 1 and "" or "s")
			end
		elseif d.kind == "buyAH" or d.kind == "buyVendor" then
			lines[#lines + 1] = format("Paid %s (%s each); %d still in stock.", B.Money(r.c), B.Money(r.c and r.c / r.q), r.l or 0)
		elseif d.kind == "posted" then
			lines[#lines + 1] = format("Posted at %s; deposit %s.", B.Money(r.p), r.d and B.Money(r.d) or "not known")
		elseif d.kind == "expired" or d.kind == "cancelled" then
			lines[#lines + 1] = format("The items came back; the deposit %s is lost.", r.d and B.Money(r.d) or "(not known)")
		else
			if r.money then
				lines[#lines + 1] = format("Gold: %s. A transfer between characters: never income, never profit.", B.Money(r.money))
			else
				lines[#lines + 1] = format("Cost carried with the units: %s%s. No sale, no profit.", B.Money(r.c or 0), (r.u or 0) > 0 and format("; %d unit%s of unknown cost", r.u, r.u == 1 and "" or "s") or "")
			end
		end
	elseif view == "sales" then
		card.title:SetText(format("Sale of %s", it and it.name or ("item " .. tostring(d.id))))
		lines[#lines + 1] = format("%s by %s: %d unit%s, price %s, cut %s, revenue %s.", date("%Y-%m-%d %H:%M", d.t), d.who, d.q, d.q == 1 and "" or "s", B.Money(d.gross), B.Money(d.cut), B.Money(d.revenue))
		lines[#lines + 1] = d.result and format("Result of the units of known cost: %s.", B.Signed(d.result)) or "Unknown cost: no result computed."
	elseif view == "auctions" then
		card.title:SetText(format("Posting of %s", it and it.name or ("item " .. tostring(d.id))))
		lines[#lines + 1] = format("%s by %s: %d at %s, deposit %s. State: %s%s.", date("%Y-%m-%d %H:%M", d.t), d.who, d.q, B.Money(d.price), d.deposit and B.Money(d.deposit) or "not known",
			d.state, d.ended and (" (" .. date("%m-%d %H:%M", d.ended) .. ")") or "")
	end
	card.text:SetText(table.concat(lines, "\n"))
	card:Show()
end

function page.Refresh(p)
	local st = DB().settings
	local view = st.businessView
	if not p.lists[view] then
		view = "inventory"
		st.businessView = view
	end
	for _, b in ipairs(p.views) do
		B.SetOn(b, b.view == view)
	end
	for key, list in pairs(p.lists) do
		list.frame:SetShown(key == view)
	end
	local scope = B.Scope()
	local timed = view == "journal" or view == "sales"
	p.period:SetShown(timed)
	p.kind:SetShown(view == "journal")
	p.char:SetShown(true)
	if timed then
		B.SetDropdown(p.period, Eco.JOURNAL_PERIODS, st.journalPeriod, function(v)
			st.journalPeriod = v
		end)
	end
	B.SetDropdown(p.kind, Eco.JOURNAL_TYPES, st.journalKind, function(v)
		st.journalKind = v
	end)
	B.SetDropdown(p.char, CharOptions(), scope, function(v)
		st.ledgerScope = v
	end)
	p.char:ClearAllPoints()
	if view == "journal" then
		p.char:SetPoint("LEFT", p.kind, "RIGHT", 6, 0)
	elseif timed then
		p.char:SetPoint("LEFT", p.period, "RIGHT", 6, 0)
	else
		p.char:SetPoint("TOPLEFT", 0, -34)
	end
	local list = p.lists[view]
	local data, empty, note
	if view == "inventory" then
		data = Eco.Inventory(scope)
		empty = "No stock followed. What you buy at the auction house (mails) or at a merchant and resell is followed here."
		local unknown = 0
		for _, d in ipairs(data) do
			unknown = unknown + d.unknown
		end
		note = unknown > 0 and format("%d unit%s of Unknown cost (received without a known cost)", unknown, unknown == 1 and "" or "s") or "Est. Value: an estimate, never profit"
	elseif view == "auctions" then
		data = Eco.AuctionList(scope)
		empty = "No posting seen yet: post at the auction house, then open your mailbox for their outcome."
		note = "States from the mails read after each posting"
	elseif view == "sales" then
		local periods = { ["24h"] = DAY, ["7d"] = 7 * DAY, ["30d"] = 30 * DAY }
		data = Eco.SalesList(scope, periods[st.journalPeriod] and time() - periods[st.journalPeriod] or 0)
		empty = "No sale in this period. Sales are read from the auction house mails (open your mailbox) and from merchants."
		note = "Result: units of known cost only"
	else
		data = Eco.JournalEntries(scope, st.journalPeriod, st.journalKind)
		empty = "Nothing in this period. Every operation seen is written here: auction house mails (open your mailbox), merchants, postings, mails sent."
		note = format("%d operation%s", #data, #data == 1 and "" or "s")
	end
	p.note:SetText(note or "")
	list:SetData(data)
	list.empty:SetText(empty)
	-- the details open (journal, sales, auctions)
	local d
	if p.state.detail and view ~= "inventory" then
		for _, x in ipairs(data) do
			if x.key == p.state.detail then
				d = x
			end
		end
	end
	list.frame:ClearAllPoints()
	list.frame:SetPoint("TOPLEFT", 0, -64)
	if d then
		Detail(p, view, d)
		list.frame:SetPoint("BOTTOMRIGHT", p.detail, "TOPRIGHT", 0, 6)
	else
		p.detail:Hide()
		list.frame:SetPoint("BOTTOMRIGHT", 0, 0)
	end
end

function page.OnKey(p, key)
	local view = DB().settings.businessView
	local list = p.lists[view]
	if key == "LEFT" and p.state.detail then
		p.state.detail = nil
		Eco.Refresh()
		return true
	end
	return list and B.ListKey(list, key, function(d)
		list.onClick(d, "LeftButton")
	end) or false
end
