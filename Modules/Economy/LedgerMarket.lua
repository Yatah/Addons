--[[
	WC3 Console - The Goblin Ledger, Market: look at the market without
	drowning in it. Search, categories, favourites; Item, Current Price,
	Typical Price, Listed Quantity, Data Quality. A click: its history
	(prices and quantities over 7, 14 or 28 days), the volumes, the figures
	and what they compare (periods told), the scan they come from (quick:
	the lowest auction only; full: every auction).
	  current price  the lowest of the last scan (listed now)
	  typical price  the median of the daily prices of the last 14 days
	                 (5 days at least, else Not enough data)
	  trend          the median of the last 3 days against the 14 day one
	  supply         the listed quantity, 3 days against 14
	Figures: Opportunities.lua (MarketRows), Data.lua (Indicators).
]]

local _, ns = ...
local Eco = ns.Economy
local floor, max, min, format, abs = math.floor, math.max, math.min, string.format, math.abs
local ipairs, tostring = ipairs, tostring

local B, T = Eco.Book, Eco.Theme
local DB, Item, Icon = Eco.DB, Eco.Item, Eco.Icon

local page = B.Register({
	key = "market", label = "Market", icon = [[Interface\Icons\INV_Misc_Bag_10]], order = 4,
	about = "Search the market, your favourites, the history and the figures of an item.",
})

-- a change in words: never cut, "Not enough data" without a reference
-- (above +999 %: "x N", the times the reference)
local function Change(x)
	if x == nil then
		return "Not enough data"
	elseif x >= 9.99 then
		return format("x%.0f", 1 + x)
	end
	return format("%+d%%", floor(x * 100 + 0.5))
end
Eco.ChangeText = Change

local STAR = "|TInterface\\Icons\\INV_Misc_Coin_02:12:12|t "

local COLUMNS = {
	{ label = "Item", width = 0, icon = function(d)
		return Icon(d.id)
	end, text = function(d)
		local it = (d.link and Item(d.link)) or Item(d.id)
		local r, g, b = Eco.QualityColor(it and it.quality)
		return (d.fav and STAR or "") .. (it and it.name or ("item " .. tostring(d.id))), r, g, b
	end, sort = function(d)
		local it = (d.link and Item(d.link)) or Item(d.id)
		return it and it.name:lower()
	end, desc = false, tip = "A star: one of your favourites (right click)." },
	{ label = "Current Price", width = 104, align = "RIGHT", text = function(d)
		if not d.current then
			return "Not listed now", 0.6, 0.6, 0.6
		end
		return B.Money(d.current)
	end, sort = function(d)
		return d.current
	end, tip = "The lowest price of the last scan." },
	{ label = "Typical Price", width = 104, align = "RIGHT", text = function(d)
		if not d.typical then
			return "Not enough data", 1, 0.75, 0.2
		end
		return B.Money(d.typical)
	end, sort = function(d)
		return d.typical
	end, tip = "The median of the daily prices of the last 14 days (5 days of prices at least)." },
	{ label = "Listed Quantity", width = 110, align = "RIGHT", text = function(d)
		if not d.listed then
			return "-", 0.6, 0.6, 0.6
		end
		return Eco.Thousands(d.listed) .. (d.quick and " (quick)" or "")
	end, sort = function(d)
		return d.listed
	end, tip = "Units listed in the last scan. (quick): a quick scan, its total as the auction house browse list gives it." },
	{ label = "Data Quality", width = 118, text = function(d)
		local c = d.quality >= 3 and B.GREEN or (d.quality >= 1 and B.AMBER or B.RED)
		return (d.quality >= 3 and "*** " or (d.quality == 2 and "** " or (d.quality == 1 and "* " or "- "))) .. Eco.QUALITY[d.quality], c[1], c[2], c[3]
	end, sort = function(d)
		return d.quality
	end },
}

function page.Create(p)
	p.state = p.state or {}
	page.spread = true
	local S = p.S
	local title = B.Text(S, "title")
	title:SetPoint("TOPLEFT", 0, 0)
	title:SetText("Market")
	p.searchBox = B.Input(S, 180, function(text)
		p.state.search = text
		p.list.offset = 0
		Eco.Refresh()
	end)
	p.searchBox:SetPoint("LEFT", title, "RIGHT", 24, -2)
	B.Tip(p.searchBox, "Search", "Part of an item's name (the items already known by the game).")
	p.category = B.Dropdown(S, 190)
	p.category:SetPoint("LEFT", p.searchBox, "RIGHT", 10, 2)
	p.favorites = B.Button(S, "Favourites", 100, function()
		local st = DB().settings
		st.marketFavorites = not st.marketFavorites
		Eco.Refresh()
	end)
	p.favorites:SetPoint("LEFT", p.category, "RIGHT", 6, 0)
	p.count = B.Text(S, "muted")
	p.count:SetPoint("TOPLEFT", 0, -32)
	p.count:SetPoint("TOPRIGHT", S, "TOPRIGHT", 0, -32)
	local list = B.List(S, COLUMNS, 1, 28)
	list.sortDesc = false
	list.frame:SetPoint("TOPLEFT", 0, -50)
	list.frame:SetPoint("BOTTOMRIGHT", 0, 0)
	list.onClick = function(d, button)
		if button == "RightButton" then
			Eco.ToggleFavorite(d.key)
			Eco.Refresh()
		elseif IsShiftKeyDown() then
			local it = Item(d.id)
			Eco.Search(it and it.name)
		else
			list.selected = d.key
			p.state.detail = d.key
			Eco.Refresh()
		end
	end
	list.onEnter = function(owner, d)
		Eco.View.MarketTooltip(owner, Eco.MarketRow(d.key, d.rec, Eco.LedgerStats()[d.id]))
	end
	p.list = list

	-- the history of an item
	local h = CreateFrame("Frame", nil, S)
	h:SetPoint("TOPLEFT", 0, -32)
	h:SetPoint("BOTTOMRIGHT")
	h:Hide()
	p.hist = h
	h.back = B.Button(h, "Back to the market", 150, function()
		p.state.detail = nil
		Eco.Refresh()
	end)
	h.back:SetPoint("TOPLEFT", 0, 0)
	h.ranges = {}
	local prev = h.back
	for _, n in ipairs({ 7, 14, 28 }) do
		local b = B.Button(h, n .. " days", 70, function()
			p.state.days = n
			Eco.Refresh()
		end)
		b:SetPoint("LEFT", prev, "RIGHT", prev == h.back and 12 or 4, 0)
		b.days = n
		h.ranges[#h.ranges + 1] = b
		prev = b
	end
	h.fav = B.Button(h, "Favourite", 100, function()
		Eco.ToggleFavorite(p.state.detail)
		Eco.Refresh()
	end)
	h.fav:SetPoint("LEFT", prev, "RIGHT", 12, 0)
	h.name = B.Text(h, "heading")
	h.name:SetPoint("LEFT", h.fav, "RIGHT", 12, 0)
	h.name:SetPoint("TOPRIGHT", h, "TOPRIGHT", 0, -7)
	h.price = Eco.NewChart(h)
	h.supply = Eco.NewChart(h)
	for _, c in ipairs({ h.price, h.supply }) do
		T.Skin(c.bg, "line", "card")
		T.Skin(c.title, "text", "small")
		T.Skin(c.high, "text", "muted")
		T.Skin(c.low, "text", "muted")
	end
	h.stats = B.Text(h, "body")
	h.stats:SetWordWrap(true)
	h.stats:SetJustifyV("TOP")
	h:SetScript("OnSizeChanged", function(self, w, hh)
		local cw = max(120, w - 70 - 300)
		local ch = max(30, (hh - 40 - 22 - 30) / 2)
		self.price:ClearAllPoints()
		self.price:SetPoint("TOPLEFT", self, "TOPLEFT", 66, -44)
		self.price:SetSize(cw, ch)
		self.supply:ClearAllPoints()
		self.supply:SetPoint("TOPLEFT", self.price, "BOTTOMLEFT", 0, -26)
		self.supply:SetSize(cw, ch)
		self.stats:ClearAllPoints()
		self.stats:SetPoint("TOPLEFT", self.price, "TOPRIGHT", 18, 0)
		self.stats:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 0)
	end)
end

-- the history: prices (dots and line, the typical price drawn across) and
-- quantities (bars: listed, near the price) per 12 h for the stackables,
-- per day for the gear
local function DrawHistory(p, d)
	local h = p.hist
	local rec, ind = d.rec, d.ind
	local n = p.state.days or 14
	for _, b in ipairs(h.ranges) do
		B.SetOn(b, b.days == n)
	end
	local half = rec.hp ~= nil
	local per = half and 2 or 1
	local slots = n * per
	local today = Eco.Today()
	h.price.title:SetText(half and "Price per 12 h (line: the typical price)" or "Price per day (line: the typical price)")
	h.supply.title:SetText(half and "Listed per 12 h (bright: near the price)" or "Listed per day")
	local daily, dTotals, dNears
	if not half then
		daily, dTotals, dNears = Eco.Daily(rec)
	end
	local prices, totals, nears = {}, {}, {}
	local pMin, pMax, qMax = nil, nil, 0
	for i = 1, slots do
		local pr, total, near
		if half then
			local k = (today - n + 1) * 2 + i - 1
			if rec.hp[k] then
				pr, total, near = Eco.UnpackP(rec.hp[k])
			end
		else
			local k = today - n + i
			pr, total, near = daily[k], dTotals and dTotals[k], dNears and dNears[k]
		end
		prices[i], totals[i], nears[i] = pr, total, near
		if pr then
			pMin, pMax = min(pMin or pr, pr), max(pMax or pr, pr)
		end
		if total then
			qMax = max(qMax, total)
		end
	end
	local typical = d.typical
	if typical then
		pMin, pMax = min(pMin or typical, typical), max(pMax or typical, typical)
	end
	local c = h.price
	local w, hh = c:GetWidth(), c:GetHeight()
	local bw = w / slots
	local r, g, b = T.Color("chart")
	if pMin and w > 10 and hh > 10 then
		local pad = max((pMax - pMin) * 0.1, pMax * 0.02, 1)
		local lo, hi = max(0, pMin - pad), pMax + pad
		local function Y(v)
			return (v - lo) / (hi - lo) * (hh - 4) + 2
		end
		c.high:SetText(B.Money(hi))
		c.low:SetText(B.Money(lo))
		if typical then
			local t = Eco.ChartTexture(c, "BORDER")
			t:SetColorTexture(T.Color("metal"))
			t:SetHeight(1)
			t:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 0, Y(typical))
			t:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, Y(typical))
		end
		local px, py
		for i = 1, slots do
			if prices[i] then
				local x, y = (i - 0.5) * bw, Y(prices[i])
				if px then
					Eco.ChartLine(c, px, py, x, y, r, g, b)
				end
				local dot = Eco.ChartTexture(c, "OVERLAY")
				dot:SetColorTexture(r, g, b, 1)
				dot:SetSize(5, 5)
				dot:SetPoint("CENTER", c, "BOTTOMLEFT", x, y)
				px, py = x, y
			end
		end
	else
		c.high:SetText("")
		c.low:SetText("Not enough data")
	end
	Eco.ChartDone(c)
	c = h.supply
	hh = c:GetHeight()
	c.high:SetText(qMax > 0 and Eco.Thousands(qMax) or "")
	c.low:SetText(qMax > 0 and "0" or "Not enough data")
	if qMax > 0 and hh > 10 then
		for i = 1, slots do
			if totals[i] then
				local t = Eco.ChartTexture(c, "ARTWORK")
				t:SetColorTexture(T.Color("muted"))
				t:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", (i - 1) * bw + 1, 0)
				t:SetSize(max(1, bw - 2), max(1, totals[i] / qMax * (hh - 2)))
				if nears[i] and nears[i] > 0 then
					local near = Eco.ChartTexture(c, "OVERLAY")
					near:SetColorTexture(T.Color("chart"))
					near:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", (i - 1) * bw + 1, 0)
					near:SetSize(max(1, bw - 2), max(1, nears[i] / qMax * (hh - 2)))
				end
			end
		end
	end
	Eco.ChartDone(c)
	-- the figures, their periods told
	local _, realm = DB()
	local function L(label, value)
		return format("|cff%s%s|r  %s", "808080", label, value)
	end
	local lines = {
		L("Current price", d.current and B.Money(d.current) or "Not listed now"),
		L("Typical price (14-day median)", d.typical and B.Money(d.typical) or "Not enough data"),
		L("Trend (3 days vs 14)", Change(ind and ind.trend)),
		L("Spread (Q75 - Q25) / median, 14 days", ind and ind.spread and format("%d%%", floor(ind.spread * 100 + 0.5)) or "Not enough data"),
		L("Low / high quartile, 14 days", ind and ind.q25 and (B.Money(ind.q25) .. " / " .. B.Money(ind.q75)) or "Not enough data"),
		" ",
		L("Listed now", d.listed and Eco.Thousands(d.listed) or "-"),
		L("Near the price now", rec.qn and Eco.Thousands(rec.qn) or "Not enough data (full scan)"),
		L("Supply (listed, 3 days vs 14)", Change(ind and ind.supply)),
		L("Listed per day, 3 / 14 days", ind and ind.vol14 and (Eco.Thousands(ind.vol3 or 0) .. " / " .. Eco.Thousands(ind.vol14)) or "Not enough data"),
		" ",
		L("History", ind and format("%d days of prices, %d of quantities", ind.days, ind.volDays or 0) or "none"),
		L("Data quality", Eco.QUALITY[d.quality]),
		L("From", format("the %s scan of %s%s", realm.lastMode or "?", Eco.Ago(realm.lastScan),
			realm.lastMode == "quick" and (" (lowest price and total only; the full scan of " .. Eco.Ago(realm.fullAt) .. " for the rest)") or "")),
	}
	h.stats:SetText(table.concat(lines, "\n"))
end

function page.Refresh(p)
	local st = DB().settings
	local cats = {}
	for _, c in ipairs(Eco.CATEGORIES) do
		cats[#cats + 1] = { value = c.key, label = c.label }
	end
	B.SetDropdown(p.category, cats, Eco.CATEGORIES[st.marketCategory] and st.marketCategory or "all", function(v)
		st.marketCategory = v
		p.list.offset = 0
	end)
	B.SetOn(p.favorites, st.marketFavorites)
	if p.searchBox:GetText() ~= (p.state.search or "") and not p.searchBox:HasFocus() then
		p.searchBox:SetText(p.state.search or "")
	end
	local rows, loading = Eco.MarketRows(p.state.search, st.marketCategory, st.marketFavorites)
	local _, realm = DB()
	p.count:SetText(format("%s items%s  -  last scan %s (%s)%s", Eco.Thousands(#rows), loading > 0 and format(", %d not loaded yet", loading) or "",
		Eco.Ago(realm.lastScan), realm.lastMode or "none", "  -  click: history, right click: favourite, shift-click: search"))
	local detail
	if p.state.detail then
		for _, d in ipairs(rows) do
			if d.key == p.state.detail then
				detail = d
			end
		end
		if not detail then
			local rec = realm.items[p.state.detail]
			if rec then
				local all = Eco.MarketRows(nil, nil, false)
				for _, d in ipairs(all) do
					if d.key == p.state.detail then
						detail = d
					end
				end
			end
		end
	end
	p.list.frame:SetShown(detail == nil)
	p.hist:SetShown(detail ~= nil)
	p.searchBox:SetShown(detail == nil)
	p.category:SetShown(detail == nil)
	p.favorites:SetShown(detail == nil)
	p.count:SetShown(detail == nil)
	if detail then
		local it = (detail.link and Item(detail.link)) or Item(detail.id)
		p.hist.name:SetText(it and it.name or ("item " .. tostring(detail.id)))
		p.hist.fav:SetText(detail.fav and "Unfavourite" or "Favourite")
		DrawHistory(p, detail)
	else
		p.state.detail = nil
		p.list:SetData(rows)
		p.list.empty:SetText(st.marketFavorites and "No favourite yet: right click an item of the market." or
			(realm.lastScan and "Nothing matches." or "No scan yet: open the auction house and press Scan."))
	end
end

function page.OnKey(p, key)
	if p.state.detail then
		if key == "LEFT" or key == "BACKSPACE" then
			p.state.detail = nil
			Eco.Refresh()
			return true
		end
		return false
	end
	return B.ListKey(p.list, key, function(d)
		p.list.onClick(d, "LeftButton")
	end)
end
