--[[
	WC3 Console - The Goblin Ledger, Make Gold: by method.
	  left   the four methods (Buy & Resell, Craft & Sell, Disenchant, Craft
	         & Disenchant): what each is, what it needs, how many verified
	         opportunities; unavailable, missing data and no opportunity are
	         three different things; the filters of the method
	  right  its opportunities: Item, Cost, Estimated Net Profit, Data
	         Quality (a mark before the item: verified or to review)
	  sheet  (across the book, on a click) What to buy -> What to do ->
	         Expected outcome; Eligibility, Data Quality and the estimate
	         apart; the fees and the assumptions. Back to opportunities
	         finds the list as it was.
	The ledger prepares and explains: it searches the auction house on a
	click, it never buys, sells or disenchants. Figures: Opportunities.lua.
]]

local _, ns = ...
local Eco = ns.Economy
local floor, max, min, format = math.floor, math.max, math.min, string.format
local ipairs, pairs, tostring = ipairs, pairs, tostring

local B, T, V = Eco.Book, Eco.Theme, Eco.View
local DB, Item, BaseID, Icon = Eco.DB, Eco.Item, Eco.BaseID, Eco.Icon

local page = B.Register({
	key = "gold", label = "Make Gold", icon = [[Interface\Icons\INV_Misc_Coin_17]], order = 2,
	about = "The ways to make gold, their verified opportunities, a sheet for each: what to buy, what to do, what to expect.",
})

local STATE_TEXT = { ok = "positive", unavailable = "negative", missing = "uncertain", none = "muted" }
local CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t "
local REVIEW = "|TInterface\\RaidFrame\\ReadyCheck-Waiting:14:14|t "

------------------------------------------------------------------------
-- The list of opportunities
------------------------------------------------------------------------

local function ItemCell(row)
	local mark = row.verified and CHECK or REVIEW
	if row.label then
		local r, g, b = Eco.QualityColor(row.itemQuality)
		return mark .. row.label, r, g, b
	end
	local it = (row.link and Item(row.link)) or Item(row.id)
	if it then
		local r, g, b = Eco.QualityColor(it.quality)
		return mark .. it.name, r, g, b
	end
	return mark .. "item " .. tostring(row.id), 0.6, 0.6, 0.6
end

local COLUMNS = {
	{ label = "Item", width = 0, icon = function(row)
		return row.icon and Icon(row.icon) or Icon(row.id)
	end, text = ItemCell, sort = function(row)
		if row.goal then return format("%03d:%s",row.required,row.label) end
		local text = ItemCell(row)
		return text:lower()
	end, desc = false, tip = "Green mark: verified (eligible, data good enough, advised by the computation). Question mark: to review." },
	{ label = "Cost", width = 96, align = "RIGHT", text = function(row)
		if row.goal then return "-" end
		if not row.cost then
			return "Unknown cost", 1, 0.75, 0.2
		end
		return B.Money(row.cost)
	end, sort = function(row)
		return row.cost
	end, tip = "What the opportunity asks to buy (its sheet: the exact items)." },
	{ label = "Est. Net Profit", width = 112, align = "RIGHT", text = function(row)
		if row.goal then return "-" end
		if not row.net then
			return "Not enough data", 1, 0.75, 0.2
		end
		local c = row.net >= 0 and B.GREEN or B.RED
		return B.Signed(row.net), c[1], c[2], c[3]
	end, sort = function(row)
		return row.net
	end, tip = "An estimate after the cut and the fees: never a promise." },
	{ label = "Data Quality", width = 100, text = function(row)
		if row.goal then return row.delta > 0 and "Skill goal" or "Check in game", 1, 0.75, 0.2 end
		local c = row.quality >= 3 and B.GREEN or (row.quality >= 1 and B.AMBER or B.RED)
		return (row.quality >= 3 and "*** " or (row.quality == 2 and "** " or (row.quality == 1 and "* " or "- "))) .. Eco.QUALITY[row.quality], c[1], c[2], c[3]
	end, sort = function(row)
		return row.quality
	end, tip = "How far the prices behind it can be trusted: days of history, spread, the age and the kind of the last scan." },
}

local TRADE_COLUMNS = {
 {label="Item",width=0,icon=function(r)return Icon(r.id) end,text=ItemCell,sort=function(r)return r.label end,desc=false},
 {label="Buyout",width=84,text=function(r)return r.cost and ((r.quick and "~" or "")..B.Money(r.cost)) or "-" end,sort=function(r)return r.cost end},
 {label="DE value",width=84,text=function(r)return r.expected and B.Money(r.expected) or "-" end,sort=function(r)return r.expected end},
 {label="Est. profit",width=84,text=function(r)return r.net and B.Signed(r.net) or "-" end,sort=function(r)return r.net end},
 {label="Margin",width=60,text=function(r)return r.margin and format("%.1f%%",r.margin) or "-" end,sort=function(r)return r.margin end},
 {label="Status",width=112,text=function(r)
  if r.bagItem then return r.marked and "Marked" or "Confirm item" end
  if r.journal then return "Purchased" end
  if r.excludedItem then return "Excluded" end
  return Eco.DETradeStatus(r)
 end}
}

local TOOLTIP = {
	resell = function(owner, row)
		V.DealTooltip(owner, row.d)
	end,
	craft = function(owner, row)
		V.CraftTooltip(owner, row.d)
	end,
	de = function(owner, row)
		if row.trade or row.bagItem or row.journal or row.excludedItem then
            GameTooltip:SetOwner(owner,"ANCHOR_RIGHT");GameTooltip:AddLine(row.label);GameTooltip:AddLine(row.why or Eco.DETradeStatus(row),1,0.8,0.2,true);GameTooltip:Show()
        elseif row.goal then
            GameTooltip:SetOwner(owner,"ANCHOR_RIGHT")
            GameTooltip:AddLine(row.label)
            GameTooltip:AddLine(row.why,1,0.75,0.2,true)
            for _,reason in ipairs(row.reasons) do GameTooltip:AddLine(reason,1,1,1,true) end
            GameTooltip:Show()
        else V.EnchantTooltip(owner, row.d) end
	end,
	craftde = function(owner, row)
		V.SynergyTooltip(owner, row.d)
	end,
}

------------------------------------------------------------------------
-- A text block with lines, made once, reused (the sheet)
------------------------------------------------------------------------

local function Block(parent)
	local b = { parent = parent, lines = {}, used = 0 }
	return b
end

local function Line(b, kind, left, right, colour)
	b.used = b.used + 1
	local l = b.lines[b.used]
	if not l then
		l = {}
		l.left = B.Text(b.parent, "body")
		l.left:SetWordWrap(true)
		l.left:SetJustifyV("TOP")
		l.right = B.Text(b.parent, "body", "RIGHT")
		b.lines[b.used] = l
	end
	T.SKINS.text(l.left, T.Current(), kind)
	T.SKINS.text(l.right, T.Current(), kind == "heading" and "heading" or "body")
	l.left:SetText(T.ReadableText(left or ""))
	l.right:SetText(T.ReadableText(right or ""))
	if colour then
		l.left:SetTextColor(T.Color(colour))
		if right then
			l.right:SetTextColor(T.Color(colour))
		end
	end
	l.kind = kind
	return l
end

-- lay the lines out from the top, `width` wide; the height used
local function Layout(b, width)
	local y = 0
	for i = 1, b.used do
		local l = b.lines[i]
		if l.kind == "heading" and i > 1 then
			y = y - 8
		end
		l.left:ClearAllPoints()
		l.left:SetPoint("TOPLEFT", b.parent, "TOPLEFT", 0, y)
		local rw = l.right:GetText() ~= "" and min(width * 0.45, (l.right:GetStringWidth() or 0) + 4) or 0
		l.left:SetWidth(max(40, width - rw - (rw > 0 and 8 or 0)))
		l.right:ClearAllPoints()
		l.right:SetPoint("TOPRIGHT", b.parent, "TOPLEFT", width, y)
		l.right:SetWidth(rw)
		l.left:Show()
		l.right:SetShown(rw > 0)
		local h = max(l.left:GetStringHeight() or 14, 14)
		y = y - h - 3
	end
	for i = b.used + 1, #b.lines do
		b.lines[i].left:Hide()
		b.lines[i].right:Hide()
	end
	b.used = 0
	return -y
end

-- a scrolling area (the mouse wheel), its content as wide as it
local function Scroll(parent)
	local s = CreateFrame("ScrollFrame", nil, parent)
	local c = CreateFrame("Frame", nil, s)
	c:SetSize(10, 10)
	s:SetScrollChild(c)
	s:EnableMouseWheel(true)
	s:SetScript("OnMouseWheel", function(self, delta)
		local maxV = max(0, c:GetHeight() - self:GetHeight())
		self:SetVerticalScroll(max(0, min(maxV, self:GetVerticalScroll() - delta * 30)))
	end)
	s:SetScript("OnSizeChanged", function(self, w)
		c:SetWidth(max(10, w))
	end)
	s.content = c
	return s
end

------------------------------------------------------------------------
-- Creation
------------------------------------------------------------------------

local function MethodCard(p, m, i)
	local b = CreateFrame("Button", nil, p.L)
	b:SetHeight(70)
	b:SetPoint("TOPLEFT", 0, -42 - (i - 1) * 76)
	b:SetPoint("TOPRIGHT", p.L, "TOPRIGHT", 0, -42 - (i - 1) * 76)
	T.Skin(b, "card")
	b.sel = b:CreateTexture(nil, "BACKGROUND", nil, 2)
	b.sel:SetAllPoints()
	T.Skin(b.sel, "line", "select")
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetSize(30, 30)
	b.icon:SetPoint("TOPLEFT", 8, -8)
	b.icon:SetTexture(m.icon)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.title = B.Text(b, "heading")
	b.title:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 8, 0)
	b.title:SetText(m.label)
	b.status = B.Text(b, "small", "RIGHT")
	b.status:SetPoint("BOTTOMRIGHT", -10, 8)
	b.status:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 46, 8)
	b.explain = B.Text(b, "muted")
	b.explain:SetPoint("TOPLEFT", b.title, "BOTTOMLEFT", 0, -3)
	b.explain:SetPoint("TOPRIGHT", b, "TOPRIGHT", -8, -25)
	b.explain:SetWordWrap(true)
	b.explain:SetJustifyV("TOP")
	b.explain:SetHeight(16)
	b.explain:SetWordWrap(false)
	b.explain:SetText(m.explain)
	b:SetHighlightTexture([[Interface\QuestFrame\UI-QuestTitleHighlight]], "ADD")
	b:SetScript("OnClick", function()
		DB().settings.goldMethod = m.key
		p.state.sheet = nil
		B.Spread(p, false)
		Eco.Refresh()
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(m.label, 1, 0.82, 0)
		GameTooltip:AddLine(m.explain, 1, 1, 1, true)
		GameTooltip:AddLine("Needs: " .. m.prereq, 0.8, 0.8, 0.8, true)
		local s = self.summary
		if s then
			GameTooltip:AddLine(" ")
			for _, n in ipairs(s.needs) do
				GameTooltip:AddLine((n.met and "|cff40ff40OK|r  " or "|cffff6060Missing|r  ") .. n.text, 1, 1, 1, true)
			end
		end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	b.key = m.key
	return b
end

function page.Create(p)
	p.state = p.state or {}
	local L, R, S = p.L, p.R, p.S
	local title = B.Text(L, "title")
	title:SetPoint("TOPLEFT", 0, 0)
	title:SetText("Make Gold")
	local fl = B.Flourish(L)
	fl:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -6, -2)
	p.cards = {}
	for i, m in ipairs(Eco.METHODS) do
		p.cards[i] = MethodCard(p, m, i)
	end
	-- the filters of the method, under the cards
	local fy = -42 - 4 * 76 - 12
	p.filterLabel = B.Text(L, "heading")
	p.filterLabel:SetPoint("TOPLEFT", 0, fy)
	p.drop1 = B.Dropdown(L, 264)
	p.drop1:SetPoint("TOPLEFT", 0, fy - 18)
	p.drop2 = B.Dropdown(L, 264)
	p.drop2:SetPoint("TOPLEFT", p.drop1, "BOTTOMLEFT", 0, -5)
	p.drop3 = B.Dropdown(L, 264)
	p.drop3:SetPoint("TOPLEFT", p.drop2, "BOTTOMLEFT", 0, -5)
	p.modeButton = B.Button(L, "Gold", 110, function()
		local st = DB().settings
		st.synMode = st.synMode == "level" and "gold" or "level"
		Eco.Refresh()
	end)
	p.modeButton:SetPoint("TOPLEFT", 0, fy - 18)
	p.estimates = B.Check(L, "Show excluded / rejected lots", function()
		return DB().settings.deAll
	end, function(v)
		DB().settings.deAll = v
		Eco.Refresh()
	end)
	p.estimates:SetPoint("TOPLEFT", -4, fy - 16)
    p.deBudgetLabel=B.Text(L,"body"); p.deBudgetLabel:SetPoint("TOPLEFT",0,fy-56);p.deBudgetLabel:SetText("Budget (gold)")
    p.deBudget=B.Number(L,100,function() return tostring(DB().settings.deCapital/10000) end,function(v)
        DB().settings.deCapital=max(0,floor(v*10000+0.5))
    end)
    p.deBudget:SetPoint("TOPLEFT",110,fy-52)
    p.deMarginLabel=B.Text(L,"body");p.deMarginLabel:SetPoint("TOPLEFT",0,fy-84);p.deMarginLabel:SetText("Min. margin %")
    p.deMargin=B.Number(L,100,function()return DB().settings.deReturn end,function(v)DB().settings.deReturn=max(0,min(10000,v)) end)
    p.deMargin:SetPoint("TOPLEFT",110,fy-80)
    B.Tip(p.deBudget,"Purchase budget","Maximum combined purchase cost in gold. Zero shows independent lots; their total is not a budgeted plan.")
	p.planText = B.Text(L, "muted")
	p.planText:SetPoint("TOPLEFT", 0, -360)
	p.planText:SetPoint("TOPRIGHT", L, "TOPRIGHT", 0, -360)
	p.planText:SetWordWrap(true)
	p.planText:SetJustifyV("TOP")
	p.planText:SetHeight(30)
    B.Tip(p.planText,"Purchase plan",function() return p.planText:GetText() end)

	-- right: the opportunities
	p.listTitle = B.Text(R, "title")
	p.listTitle:SetPoint("TOPLEFT", 0, 0)
	p.listTitle:SetPoint("TOPRIGHT", R, "TOPRIGHT", -205, 0)
    p.deView = B.Dropdown(R, 195)
    p.deView:SetPoint("TOPRIGHT",R,"TOPRIGHT",0,0)
	p.listNote = B.Text(R, "muted")
	p.listNote:SetPoint("TOPLEFT", 0, -28)
	p.listNote:SetPoint("TOPRIGHT", R, "TOPRIGHT", 0, -28)
	local list = B.List(R, COLUMNS, 3)
	list.frame:SetPoint("TOPLEFT", 0, -48)
	list.frame:SetPoint("BOTTOMRIGHT", 0, 0)
	list.onClick = function(row, button)
		if button == "RightButton" then
			local name = row.id and Item(row.id) and Item(row.id).name
			if name then
				Eco.Search(name)
			end
			return
		end
		list.selected = row.key
		if row.trade or row.bagItem or row.journal or row.excludedItem then p.tradeList.selected=row.key end
		p.state.sheet = row.key
        if row.trade then Eco.DERecheck(row) end
		B.Spread(p, true)
		Eco.Refresh()
	end
	list.onEnter = function(owner, row)
		local fn = TOOLTIP[row.method]
		if fn then
			ns.Try("ledger tooltip", fn, owner, row)
		end
	end
    p.list = list
    p.tradeList=B.List(R,TRADE_COLUMNS,4)
    p.tradeList.frame:SetPoint("TOPLEFT",0,-48);p.tradeList.frame:SetPoint("BOTTOMRIGHT",0,0)
    p.tradeList.onEnter=list.onEnter
    p.tradeList.onClick=list.onClick
    p.tradeList.frame:Hide()
    p.exclusionTerms=CreateFrame("EditBox",nil,R,"InputBoxTemplate")
    p.exclusionTerms:SetWidth(300)
    B.DockControl(p.exclusionTerms)
    p.exclusionTerms:SetAutoFocus(false);p.exclusionTerms:SetHeight(22)
    p.exclusionTerms:SetPoint("TOPLEFT",6,-48);p.exclusionTerms:SetPoint("TOPRIGHT",-108,-48)
    p.saveTerms=B.Button(R,"Save filters",100,function()Eco.DESetExclusionTerms(p.exclusionTerms:GetText());p.exclusionTerms:ClearFocus() end)
    p.saveTerms:SetPoint("TOPRIGHT",0,-48)
    B.Tip(p.exclusionTerms,"Exclude names or stats","Comma-separated words, for example strength, eagle. Matching item names or stat labels are excluded. Protect valuable appearances by excluding the item from its sheet.")

	-- the sheet, across the book
	p.back = B.Button(S, "Back to opportunities", 170, function()
		p.state.sheet = nil
		B.Spread(p, false)
		Eco.Refresh()
	end)
	p.back:SetPoint("TOPLEFT", 0, 0)
	p.sheetIcon = S:CreateTexture(nil, "ARTWORK")
	p.sheetIcon:SetSize(30, 30)
	p.sheetIcon:SetPoint("TOPLEFT", 0, 0)
	p.sheetTitle = B.Text(S, "title")
	p.sheetTitle:SetPoint("TOPLEFT", S, "TOPLEFT", 40, -10)
	p.sheetTitle:SetPoint("TOPRIGHT", S, "TOP", -20, -10)
	p.sheetTitle:SetHeight(26)
	p.sheetMethod = B.Text(S, "muted")
	p.sheetMethod:SetPoint("TOPLEFT", p.sheetIcon, "BOTTOMLEFT", 0, -4)
	p.stamp = B.Stamp(S, "review")
	p.stamp:SetPoint("TOPRIGHT", S, "TOPRIGHT", 0, -10)
	p.search = B.Button(S, "Search Auction House", 180, function()
        local row=p.workflowRow
        if row and row.trade then Eco.DERecheck(row);return end
        if row and row.bagItem then Eco.DEMarkBag(row);return end
        if row and row.excludedItem then Eco.DEExclude(row.id,false);return end
		local names = p.searchNames or {}
		if #names > 0 then
			p.searchAt = (p.searchAt or 0) % #names + 1
			Eco.Search(names[p.searchAt])
		end
	end)
    p.search:SetPoint("TOPRIGHT", S, "TOPRIGHT", 0, 0)
    p.tradeOpen=B.Button(S,"Find in auction house",180,function()
        local row=p.workflowRow
        if row and row.trade then Eco.Search(Item(row.link or row.id).name) end
    end)
    p.tradeOpen:SetPoint("RIGHT",p.search,"LEFT",-8,0)
    p.tradeExclude=B.Button(S,"Exclude item",120,function()
        if p.workflowRow then Eco.DEExclude(p.workflowRow.id,true) end
    end)
    p.tradeExclude:SetPoint("RIGHT",p.tradeOpen,"LEFT",-8,0)
    p.saleFields=CreateFrame("Frame",nil,S)
    p.saleFields:SetPoint("TOPLEFT",0,-110);p.saleFields:SetPoint("TOPRIGHT",S,"TOP",-20,-110);p.saleFields:SetHeight(160)
    local saleLabel=B.Text(p.saleFields,"body");saleLabel:SetPoint("TOPLEFT",0,0);saleLabel:SetText("Net sale proceeds (gold)");saleLabel:Hide()
    p.saleNet=B.Number(p.saleFields,100,function()local pch=p.workflowRow and p.workflowRow.purchase;return pch and pch.sale and pch.sale.net/10000 or 0 end,function()end)
    p.saleNet:SetPoint("TOPRIGHT",0,0)
    local lossLabel=B.Text(p.saleFields,"body");lossLabel:SetPoint("TOPLEFT",0,-36);lossLabel:SetText("Lost deposits (gold)");lossLabel:Hide()
    p.saleLoss=B.Number(p.saleFields,100,function()local pch=p.workflowRow and p.workflowRow.purchase;return pch and pch.sale and pch.sale.loss/10000 or 0 end,function()end)
    p.saleLoss:SetPoint("TOPRIGHT",0,-36)
    -- Keep an unfinished entry until the explicit record action.
    p.saleNet:SetScript("OnEditFocusLost",function()end);p.saleLoss:SetScript("OnEditFocusLost",function()end)
    local record=B.Button(p.saleFields,"Record completed sale",190,function()
        Eco.DERecordSale(p.workflowRow,p.saleNet:GetText(),p.saleLoss:GetText())
    end)
    record:SetPoint("TOPLEFT",0,-76)
	B.Tip(p.search, "Search", "Searches the auction house for the next item of the list (the auction house must be open). It never buys.")
	-- left half: what to buy
	local half = CreateFrame("Frame", nil, S)
	half:SetPoint("TOPLEFT", 0, -56)
	half:SetPoint("BOTTOMRIGHT", S, "BOTTOM", -20, 0)
	p.buyTitle = B.Text(half, "heading")
	p.buyTitle:SetPoint("TOPLEFT", 0, 0)
	p.buyTitle:SetText("1. What to buy")
	p.buyList = B.List(half, {
		{ label = "Item", width = 0, icon = function(r)
			return Icon(r.id)
		end, text = function(r)
			local it = (r.link and Item(r.link)) or Item(r.id)
			local q = it and it.quality
			local cr, cg, cb = Eco.QualityColor(q)
			return r.name or (it and it.name) or ("item " .. tostring(r.id)), cr, cg, cb
		end },
		{ label = "Qty", width = 44, align = "RIGHT", text = function(r)
			return tostring(r.qty or "?")
		end },
		{ label = "Max unit price", width = 104, align = "RIGHT", text = function(r)
			if not r.max then
				return "Unknown", 1, 0.75, 0.2
			end
			return B.Money(r.max)
		end },
		{ label = "Total", width = 92, align = "RIGHT", text = function(r)
			if not r.total then
				return "Unknown", 1, 0.75, 0.2
			end
			return B.Money(r.total)
		end },
	}, nil, 28)
	p.buyList.frame:SetPoint("TOPLEFT", 0, -18)
	p.buyList.frame:SetPoint("TOPRIGHT", half, "TOPRIGHT", 0, -18)
	p.buyList.frame:SetHeight(180)
	p.buyList.onEnter = function(owner, r)
		local link = r.link or ("item:" .. tostring(r.id))
		GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
		pcall(GameTooltip.SetHyperlink, GameTooltip, link)
		GameTooltip:AddLine("Click: search it at the auction house", 0.5, 0.8, 1)
		GameTooltip:Show()
	end
	p.buyList.onClick = function(r)
		if r.name then
			Eco.Search(r.name)
		end
	end
	p.leftScroll = Scroll(half)
	p.leftScroll:SetPoint("TOPLEFT", p.buyList.frame, "BOTTOMLEFT", 0, -8)
	p.leftScroll:SetPoint("BOTTOMRIGHT", half, "BOTTOMRIGHT", 0, 0)
	p.leftBlock = Block(p.leftScroll.content)
	-- right half: what to do, the outcome, eligibility, data quality
	p.rightScroll = Scroll(S)
	p.rightScroll:SetPoint("TOPLEFT", S, "TOP", 20, -56)
	p.rightScroll:SetPoint("BOTTOMRIGHT", 0, 0)
	p.rightBlock = Block(p.rightScroll.content)
	-- (the book resized: the sheet laid out again)
	local pending = false
	p.rightScroll:HookScript("OnSizeChanged", function()
		if p.state.sheet and not pending then
			pending = true
			C_Timer.After(0, function()
				pending = false
				Eco.Refresh()
			end)
		end
	end)
end

------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------

local function Filters(p, method)
    p.filterLabel:Hide()
	local st = DB().settings
	p.drop1:Hide()
	p.drop2:Hide()
	p.drop3:Hide()
	p.modeButton:Hide()
    p.deBudget:SetShown(method=="de");p.deBudgetLabel:SetShown(method=="de")
    p.deMargin:SetShown(method=="de");p.deMarginLabel:SetShown(method=="de");if not p.deMargin:HasFocus() then p.deMargin:Sync() end
	p.estimates:Hide()
	p.planText:SetText("")
	if method == "resell" then
		p.filterLabel:SetText("Filters")
		local rows = Eco.ComputeDeals()
		local _, counts, subCounts = Eco.FilterDeals(rows)
		local cats = {}
		for _, c in ipairs(Eco.CATEGORIES) do
			cats[#cats + 1] = { value = c.key, label = c.label, count = counts[c.key] or 0 }
		end
		local c = Eco.CATEGORIES[st.dealCategory] or Eco.CATEGORIES.all
		B.SetDropdown(p.drop1, cats, c.key, function(v)
			st.dealCategory, st.dealSub = v, "all"
		end)
		p.drop1:Show()
		if c.subs then
			local subs = { { value = "all", label = "All", count = subCounts.all } }
			for _, s in ipairs(c.subs) do
				subs[#subs + 1] = { value = s.key, label = s.label, count = subCounts[s.key] or 0 }
			end
			B.SetDropdown(p.drop2, subs, st.dealSub, function(v)
				st.dealSub = v
			end)
			p.drop2:Show()
			p.drop3:SetPoint("TOPLEFT", p.drop2, "BOTTOMLEFT", 0, -5)
		else
			p.drop3:SetPoint("TOPLEFT", p.drop1, "BOTTOMLEFT", 0, -5)
		end
		B.SetDropdown(p.drop3, { { value = "all", label = "Any resale" }, { value = "ah", label = "Auction house" }, { value = "vendor", label = "Vendor" } }, st.dealMethod, function(v)
			st.dealMethod = v
		end)
		p.drop3:Show()
		if st.stackOnly then
			p.planText:SetText("Settings: stackables only (gear and bags resold at the auction house are hidden).")
		end
	elseif method == "craft" then
		p.filterLabel:SetText("Profession")
		local names = { { value = "all", label = "All professions" } }
		for name in pairs(Eco.Recipes()) do
			names[#names + 1] = { value = name, label = name }
		end
		B.SetDropdown(p.drop1, names, ns.cdb.ecoProfession or "all", function(v)
			ns.cdb.ecoProfession = v ~= "all" and v or nil
		end)
		p.drop1:Show()
	elseif method == "de" then
		p.filterLabel:SetText("Purchase plan")
        if not (p.deBudget.HasFocus and p.deBudget:HasFocus()) then p.deBudget:Sync() end
		p.estimates:Show()
		p.estimates:Refresh()
		local _, good, plan, info = Eco.ComputeEnchant()
		local shownPlan = info.modelPlan or plan
        p.planText:SetText(V.PlanText(shownPlan, st.deChance / 100, info, good))
        p.dePlan=shownPlan
	elseif method == "craftde" then
		p.filterLabel:SetText("Mode and crafter")
		p.modeButton:SetText(st.synMode == "level" and "Skill up" or "Gold")
		p.modeButton:Show()
		local crafters = { { value = "all", label = "All crafters" } }
		for _, cr in ipairs(Eco.Crafters()) do
			crafters[#crafters + 1] = { value = cr.key, label = cr.who .. " - " .. cr.prof }
		end
		B.SetDropdown(p.drop2, crafters, st.synWho, function(v)
			st.synWho = v
		end)
		p.drop2:ClearAllPoints()
		p.drop2:SetPoint("TOPLEFT", p.modeButton, "BOTTOMLEFT", 0, -8)
		p.drop2:Show()
	end
	if method ~= "craftde" then
		p.drop2:ClearAllPoints()
		p.drop2:SetPoint("TOPLEFT", p.drop1, "BOTTOMLEFT", 0, -5)
	end
end

local function FindRow(rows, key)
	for _, row in ipairs(rows) do
		if row.key == key then
			return row
		end
	end
end

local function DrawSheet(p, row)
	local s = Eco.OppSheet(row)
    p.workflowRow=(row.trade or row.bagItem or row.journal or row.excludedItem) and row or nil
    p.saleFields:SetShown(row.journal==true);p.buyList.frame:SetShown(not row.journal)
    if row.journal and p.saleKey~=row.key then p.saleKey=row.key;p.saleNet:Sync();p.saleLoss:Sync() end
    p.tradeOpen:SetShown(row.trade==true);p.tradeExclude:SetShown(row.trade==true)
    p.search:SetText(row.trade and "Recheck auction" or row.bagItem and "Mark purchased item" or row.excludedItem and "Restore item" or "Search Auction House")
	local m = Eco.METHODS[row.method]
	local name
	if row.label then
		name = row.label
		p.sheetIcon:SetTexture(Icon(row.icon))
	else
		local it = (row.link and Item(row.link)) or Item(row.id)
		name = it and it.name or ("item " .. tostring(row.id))
		p.sheetIcon:SetTexture(Icon(row.id))
	end
	p.sheetTitle:SetText(name)
	p.sheetMethod:SetText(m.label .. (row.note and ("  -  " .. row.note) or ""))
	p.stamp:SetKind(s.verified and "verified" or "review")
	-- what to buy
	p.buyList:SetData(s.buy)
	p.buyList.empty:SetText("Nothing to buy.")
	p.searchNames, p.searchAt = s.search, 0
	p.search:SetEnabled(row.trade or row.bagItem or row.excludedItem or #(s.search or {}) > 0)
	local lb = p.leftBlock
	Line(lb, "heading", row.goal and "Skill objective" or "Total cost", row.goal and ("Enchanting " .. row.required) or (s.total and B.Money(s.total) or "Unknown cost"), not s.total and "uncertain" or nil)
    if s.batch then
        local batch=s.batch
        Line(lb,"heading","Reduce randomness")
        if batch.quantity then
            Line(lb,"body","Suggested total items",tostring(batch.quantity))
            Line(lb,"body","Estimated total cost",B.Money(batch.cost))
            Line(lb,"body",batch.conservative and "Model chance (at least)" or "Model chance of net profit",format("%.1f%% (target %.0f%%)",math.floor(batch.chance*1000)/10,batch.target*100))
            Line(lb,"body","Expected batch profit",B.Signed(batch.profit))
            if batch.conservative then Line(lb,"muted","Conservative model bound; a smaller lot may also meet the target.") end
            Line(lb,"muted",format("At most %s per item. Total quantity, not additional purchases.",B.Money(batch.unit)))
            if batch.overBudget then Line(lb,"body","Above your budget: do not treat this as a purchase plan.",nil,"uncertain") end
            if not row.eligible then Line(lb,"body","Simulation only: confirm this item can be disenchanted before buying more.",nil,"uncertain") end
            Line(lb,"muted","Assumes independent results, these prices and the Classic yield table. Availability and sales are not guaranteed. Lost deposits are not included.")
        else
            Line(lb,"body",batch.reason,nil,"uncertain")
        end
    end
	if row.method == "de" and row.d.modelReady and not s.verified then
        Line(lb,"body","Estimated purchase lot: classic probabilities, not validated server yields. Confirm current auction prices before buying.",nil,"uncertain")
    elseif not s.verified and not p.workflowRow then
		Line(lb, "body", "Not a purchase advice: " .. (not row.eligible and "not eligible" or (row.quality < 2 and "the data is not good enough" or "the computation does not advise it")) .. " (see the right page).", nil, "uncertain")
	end
	if s.excluded and #s.excluded > 0 then
		Line(lb, "heading", "Left out (never counted)")
		for i, x in ipairs(s.excluded) do
			if i > 12 then
				Line(lb, "muted", format("... and %d more", #s.excluded - 12))
				break
			end
			Line(lb, "body", format("%s%s: %s", x.name, x.units > 0 and format(" x%d", x.units) or "", tostring(x.why)), nil, x.state == "no" and "negative" or "uncertain")
		end
	end
	p.leftScroll.content:SetHeight(Layout(lb, p.leftScroll:GetWidth()))
	-- what to do, the outcome
	local rb = p.rightBlock
	Line(rb, "heading", "2. What to do")
	for i, step in ipairs(s.todo) do
		Line(rb, "body", format("%d. %s", i, step))
	end
	if s.who then Line(rb, "body", "Who: " .. tostring(s.who), nil, "note") end
	Line(rb, "heading", "3. Expected outcome (estimate)")
	for _, o in ipairs(s.outcome) do
		Line(rb, "body", o[1], o[2])
	end
	if s.model then
		Line(rb, "muted", s.model)
	end
	Line(rb, "heading", "Eligibility")
	if s.eligibility.ok then
		Line(rb, "body", "Yes: it can be done" .. (row.method == "de" and (" - " .. tostring(row.d.how)) or "") .. ".", nil, "positive")
	elseif s.eligibility.unknown then
		-- (not known is not forbidden: the game said nothing either way)
		Line(rb, "body", "Not confirmed: " .. tostring(s.eligibility.why or "the game has not confirmed it") .. ".", nil, "uncertain")
	else
		Line(rb, "body", "No: " .. tostring(s.eligibility.why or "a requirement is missing") .. ".", nil, "negative")
	end
	Line(rb, "heading", "Data Quality: " .. tostring(s.quality.label))
	for _, why in ipairs(s.quality.reasons or {}) do
		Line(rb, "body", "- " .. why, nil, s.quality.level >= 3 and "positive" or "uncertain")
	end
	Line(rb, "heading", "Fees counted")
	for _, f in ipairs(s.fees) do
		Line(rb, "body", "- " .. f)
	end
	Line(rb, "heading", "Assumptions")
	for _, a in ipairs(s.assumptions) do
		Line(rb, "muted", "- " .. a)
	end
	p.rightScroll.content:SetHeight(Layout(rb, p.rightScroll:GetWidth()))
end

function page.Refresh(p)
	local st = DB().settings
	local method = Eco.METHODS[st.goldMethod] and st.goldMethod or "resell"
	local auctionRows=method=="de" and Eco.DEAuctionRows()
	for _, card in ipairs(p.cards) do
		local s = Eco.MethodSummary(card.key)
		card.summary = s
		card.sel:SetShown(card.key == method)
		card.status:SetText(s.line)
		if card.key=="de" and auctionRows then card.status:SetText(format("%d auction candidates (estimates)",#auctionRows)) end
		card.status:SetTextColor(T.Color(STATE_TEXT[s.state] or "muted"))
	end
	Filters(p, method)
    p.filterLabel:Hide()
	local rows = Eco.Opportunities(method)
    local view=p.state.deView or "auction"
    if method=="de" and view~="now" then
        p.estimates:Hide();p.filterLabel:SetText("Auction filters")
        p.planText:SetText(view=="auction" and "Budget: maximum per auction. Use Purchase lots for a combined budget." or "Purchase lots and auction deals have separate views.")
        if view~="auction" then
            p.deBudget:Hide();p.deBudgetLabel:Hide();p.deMargin:Hide();p.deMarginLabel:Hide()
        end
    end
    local workflow=method=="de" and (view=="auction" or view=="bags" or view=="journal" or view=="excluded")
    p.list.frame:SetShown(not workflow);p.tradeList.frame:SetShown(workflow)
    local activeList=workflow and p.tradeList or p.list
    local exclusions=workflow and view=="excluded"
    p.exclusionTerms:SetShown(exclusions);p.saveTerms:SetShown(exclusions)
    if exclusions and not p.exclusionTerms:HasFocus() then p.exclusionTerms:SetText(Eco.DEGetExclusionTerms()) end
    p.tradeList.frame:ClearAllPoints()
    p.tradeList.frame:SetPoint("TOPLEFT",0,-48);p.tradeList.frame:SetPoint("BOTTOMRIGHT",0,0)
    p.deView:SetShown(method=="de")
    local goalNote
    if method=="de" then
        B.SetDropdown(p.deView,{{value="auction",label="Auction deals"},{value="bags",label="Bought items"},{value="journal",label="Results"},{value="excluded",label="Exclusions"},{value="now",label="Purchase lots"},{value="check",label="At my skill (check)"},{value="next",label="Next 25 skill"}},p.state.deView or "auction",function(v)
            p.state.deView=v;p.state.sheet=nil;p.list.selected=nil;p.list.offset=0
            p.list.sortCol=1;p.list.sortDesc=false;p.tradeList.selected=nil;p.tradeList.offset=0;B.Spread(p,false)
        end)
        if p.state.deView=="check" or p.state.deView=="next" then rows,goalNote=Eco.DEGoals(p.state.deView) end
    end
 if workflow then
        if view=="auction" then rows=auctionRows;goalNote="Latest scan - click to recheck; DE value is an estimate"
        elseif view=="bags" then rows=Eco.DEBagRows();goalNote="Confirmed purchases only; select and mark the received item"
        elseif view=="journal" then rows=Eco.DEJournalRows();goalNote="Generated loot - collect it from the loot window; valuation is not sale proceeds"
        else rows=Eco.DEExclusionRows();goalNote="Excluded name/stat words below; select an item to restore it" end
    end
 local m = Eco.METHODS[method]
	p.listTitle:SetText(m.label)
	local verified = 0
	for _, row in ipairs(rows) do
		if row.verified then
			verified = verified + 1
		end
	end
	local summary = Eco.MethodSummary(method)
	p.listNote:SetText(summary.state == "unavailable" and summary.line
		or format("%d verified, %d to review  -  click: its sheet, right click: search it", verified, #rows - verified))
	if method=="de" then
        local ready=0
        for _,row in ipairs(rows) do if row.d.modelReady then ready=ready+1 end end
        p.listNote:SetText(format("%d purchase lots, %d rejected - model estimates; click for items",ready,#rows-ready))
    end
    if goalNote then p.listNote:SetText(goalNote) end
    activeList:SetData(rows)
    activeList.empty:SetText(summary.state == "unavailable" and summary.line or (summary.state == "missing" and summary.line) or "No opportunity right now.")
    if goalNote then activeList.empty:SetText(#rows==0 and (goalNote:find("not known") and goalNote or (workflow and "No matching items. Scan the auction house or check your filters." or "No matching candidates in the last scan.")) or "") end
 -- the sheet open: drawn again (the same opportunity)
	local row = p.state.sheet and FindRow(rows, p.state.sheet)
	if p.state.sheet and not row then
		p.state.sheet = nil
		B.Spread(p, false)
	elseif row then
		B.Spread(p, true)
		DrawSheet(p, row)
	end
end

function page.OnKey(p, key)
	if p.state.sheet then
		if key == "LEFT" or key == "BACKSPACE" then
			p.state.sheet = nil
			B.Spread(p, false)
			Eco.Refresh()
			return true
		end
		return false
	end
	return B.ListKey(p.tradeList.frame:IsShown() and p.tradeList or p.list, key, function(row)
		p.list.onClick(row, "LeftButton")
	end)
end
