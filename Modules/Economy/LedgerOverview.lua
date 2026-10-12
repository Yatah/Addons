--[[
	WC3 Console - The Goblin Ledger, Overview: how much gold, how it goes,
	what to look at next.
	  left   Your Fortune: gold on hand, its history (session, 7 days, 30
	         days, from the first session followed: never before), the
	         savings goal
	  right  Your Business: the balance change, the revenue and the realized
	         profit told apart, the gold invested in stock, its estimated
	         value (never added to the profit), what to review, what the
	         data covers
	Figures: Fortune.lua.
]]

local _, ns = ...
local Eco = ns.Economy
local floor, max, min, format = math.floor, math.max, math.min, string.format
local ipairs = ipairs

local B, T = Eco.Book, Eco.Theme
local DB = Eco.DB

local page = B.Register({
	key = "overview", label = "Overview", icon = [[Interface\Icons\INV_Misc_Coin_02]], order = 1,
	about = "How much gold you have, how it goes, and what to review next.",
})

local RANGES = { { "session", "Session" }, { "7d", "7 Days" }, { "30d", "30 Days" } }

local function Label(parent, text)
	local fs = B.Text(parent, "heading")
	fs:SetText(text)
	return fs
end

-- a figure: its label, its value, a line under it
local function Figure(parent, label, tip)
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(42)
	f.label = B.Text(f, "heading")
	f.label:SetPoint("TOPLEFT", 8, -4)
	f.label:SetText(label)
	f.value = B.Text(f, "body", "RIGHT")
	f.value:SetPoint("TOPRIGHT", -8, -4)
	f.value:SetPoint("TOPLEFT", f, "TOPLEFT", 165, -4)
	f.note = B.Text(f, "muted")
	f.note:SetPoint("TOPLEFT", f.label, "BOTTOMLEFT", 0, -3)
	f.note:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -23)
	if tip then
		f:EnableMouse(true)
		B.Tip(f, label, tip)
	end
	return f
end

function page.Create(p)
    p.spread=false
    local L,R=p.L,p.R
    local title=B.Text(L,"title"); title:SetPoint("TOPLEFT"); title:SetText("Your fortune, at a glance")
    p.rangeNote=B.Text(L,"muted"); p.rangeNote:SetPoint("TOPLEFT",0,-28)
    p.ranges={}
    local previous
    for i=#RANGES,1,-1 do
        local range=RANGES[i]
        local b=B.Button(R,range[2],82,function()
            DB().settings.historyRange=range[1]; Eco.Refresh()
        end)
        if previous then b:SetPoint("RIGHT",previous,"LEFT",-6,0) else b:SetPoint("TOPRIGHT") end
        b.range=range[1]; p.ranges[#p.ranges+1]=b; previous=b
    end
    local cards={}
    local function Metric(parent,label,tip)
        local f=B.Card(parent); f:SetHeight(104)
        f.label=B.Text(f,"heading"); f.label:SetPoint("TOPLEFT",14,-12); f.label:SetText(label)
        f.value=B.Text(f,"big"); f.value:SetPoint("TOPLEFT",14,-37); f.value:SetPoint("TOPRIGHT",-12,-37)
        f.note=B.Text(f,"muted"); f.note:SetPoint("BOTTOMLEFT",14,12); f.note:SetPoint("BOTTOMRIGHT",-12,12)
        f.fullNote=""
        f:EnableMouse(true)
        B.Tip(f,label,function() return tip.."\n\n"..f.fullNote end)
        cards[#cards+1]=f
        return f
    end
    local gold=Metric(L,"Gold on Hand","Available gold for the selected character scope.")
    p.goldValue,p.goldNote=gold.value,gold.note; p.goldMetric=gold
    p.profit=Metric(L,"Realized Profit","Completed sales with a known purchase cost, after recorded fees. Stock estimates are excluded.")
    p.invested=Metric(R,"Gold Invested","Known purchase cost of inventory still held.")
    p.stock=Metric(R,"Estimated Stock Value","Estimated resale value after the auction cut. Not a realized profit.")
    -- Long explanations belong in tooltips, never over the next metric.
    for _,f in ipairs(cards) do
        f.value:SetFont(_G.STANDARD_TEXT_FONT or [[Fonts\FRIZQT__.TTF]],23,"")
        f.value:SetWordWrap(false)
    end
    local function SizeCards()
        local width=max(1,(L:GetWidth()-12)/2)
        for i,f in ipairs(cards) do
            f:ClearAllPoints(); f:SetPoint("TOPLEFT",f:GetParent(),"TOPLEFT",((i-1)%2)*(width+12),-58); f:SetWidth(width)
        end
    end
    L:HookScript("OnSizeChanged",SizeCards); R:HookScript("OnSizeChanged",SizeCards); SizeCards()
    local history=B.Card(L); p.historyPanel=history
    history:SetPoint("TOPLEFT",0,-180)
    history:SetPoint("BOTTOMRIGHT",L,"BOTTOMRIGHT",0,112)
    local heading=Label(history,"Gold History"); heading:SetPoint("TOPLEFT",14,-12)
    p.change=B.Text(history,"small"); p.change:SetPoint("BOTTOMLEFT",14,12); p.change:SetPoint("BOTTOMRIGHT",-14,12)
    local chart=Eco.NewChart(history)
    chart:SetPoint("TOPLEFT",history,"TOPLEFT",76,-48)
    chart:SetPoint("BOTTOMRIGHT",history,"BOTTOMRIGHT",-18,46)
    T.Skin(chart.bg,"line","card")
    T.Skin(chart.high,"text","muted"); T.Skin(chart.low,"text","muted")
    chart.empty=B.Text(chart,"muted","CENTER")
    chart.empty:SetPoint("LEFT",16,0); chart.empty:SetPoint("RIGHT",-16,0); chart.empty:SetWordWrap(true)
    for i=1,3 do
        local line=B.Line(chart,"BACKGROUND"); line:SetHeight(1)
        line:SetPoint("LEFT",chart,"LEFT",0,0); line:SetPoint("RIGHT",chart,"RIGHT",0,0)
        line:SetAlpha(0.25)
        chart:HookScript("OnSizeChanged",function(self)
            line:ClearAllPoints(); line:SetPoint("BOTTOMLEFT",self,"BOTTOMLEFT",0,self:GetHeight()*i/4)
            line:SetPoint("BOTTOMRIGHT",self,"BOTTOMRIGHT",0,self:GetHeight()*i/4)
        end)
    end
    p.chart=chart
    local business=B.Card(R); p.businessPanel=business
    business:SetPoint("TOPLEFT",R,"TOPLEFT",0,-180)
    business:SetPoint("BOTTOMRIGHT",R,"BOTTOMRIGHT",0,48)
    local nextTitle=Label(business,"Next Steps"); nextTitle:SetPoint("TOPLEFT",14,-12)
    p.actions={}
    for i=1,4 do
        local b=CreateFrame("Button",nil,business)
        b:SetPoint("TOPLEFT",14,-40-(i-1)*32); b:SetPoint("TOPRIGHT",-14,-40-(i-1)*32); b:SetHeight(30)
        b.stamp=B.Stamp(b,"review"); b.stamp:SetPoint("LEFT"); b.stamp:SetSize(18,20); b.stamp.label:Hide()
        b.text=B.Text(b,"body"); b.text:SetPoint("LEFT",b.stamp,"RIGHT",8,0); b.text:SetPoint("RIGHT")
        b.text:SetWordWrap(true); b.text:SetHeight(30)
        b:SetHighlightTexture([[Interface\QuestFrame\UI-QuestTitleHighlight]],"ADD")
        b:SetScript("OnClick",function(self)
            if self.action then
                if self.action.view then DB().settings.businessView=self.action.view end
                B.Open(self.action.page)
            end
        end)
        p.actions[i]=b
    end
    p.balance=Figure(business,"Balance change","All changes to your gold balance, including purchases and transfers. Not trading profit.")
    p.balance:SetPoint("BOTTOMLEFT",8,52); p.balance:SetPoint("BOTTOMRIGHT",-8,52)
    p.revenue=Figure(business,"Sales revenue","Recorded proceeds after the auction cut.")
    p.revenue:SetPoint("BOTTOMLEFT",8,8); p.revenue:SetPoint("BOTTOMRIGHT",-8,8)
    local goal=Label(L,"Savings Goal"); goal:SetPoint("BOTTOMLEFT",0,84)
    p.goalSet=B.Button(L,"Set Goal",90,function()
        p.goalBox:SetShown(not p.goalBox:IsShown())
        if p.goalBox:IsShown() then p.goalBox:Sync(); p.goalBox:SetFocus() end
    end)
    p.goalSet:SetPoint("BOTTOMRIGHT",L,"BOTTOMRIGHT",0,76)
    p.goalBox=B.Number(L,90,function()
        local g=Eco.SavingsGoal(B.Scope()); return g and tostring(floor(g/10000)) or ""
    end,function(v) Eco.SetSavingsGoal(B.Scope(),v*10000); p.goalBox:Hide() end)
    p.goalBox:SetPoint("RIGHT",p.goalSet,"LEFT",-8,0); p.goalBox:Hide()
    p.goalBar=B.Bar(L); p.goalBar:SetPoint("BOTTOMLEFT",0,48); p.goalBar:SetPoint("BOTTOMRIGHT",0,48); p.goalBar:SetHeight(14)
    p.goalText=B.Text(L,"small"); p.goalText:SetPoint("TOPLEFT",p.goalBar,"BOTTOMLEFT",0,-8); p.goalText:SetPoint("TOPRIGHT",p.goalBar,"BOTTOMRIGHT",0,-8); p.goalText:SetHeight(32); p.goalText:SetWordWrap(true)
    p.coverage=B.Text(R,"body"); p.coverage:SetPoint("BOTTOMLEFT",0,0); p.coverage:SetPoint("BOTTOMRIGHT",0,0)
    p.coverage:SetHeight(34); p.coverage:SetWordWrap(true)
    local info=CreateFrame("Frame",nil,R); info:SetAllPoints(p.coverage); info:EnableMouse(true)
    B.Tip(info,"Tracking coverage",function() return p.coverageFull or p.coverage:GetText() end)
end

-- the gold history on the chart: a line, its low and its high
local function DrawChart(p, points, why)
	local c = p.chart
	local w, h = c:GetWidth(), c:GetHeight()
	if not points or #points < 2 or w < 20 or h < 20 then
		c.high:SetText("")
		c.low:SetText("")
		c.empty:SetText(why or "Your history starts here.\nTwo recorded snapshots are needed to draw a trend.")
		c.empty:Show()
		Eco.ChartDone(c)
		return
	end
	c.empty:Hide()
	local lo, hi = points[1].v, points[1].v
	for _, pt in ipairs(points) do
		lo, hi = min(lo, pt.v), max(hi, pt.v)
	end
	local pad = max((hi - lo) * 0.1, 100)
	lo, hi = max(0, lo - pad), hi + pad
	c.high:SetText(B.Money(hi))
	c.low:SetText(B.Money(lo))
	local t0, t1 = points[1].t, points[#points].t
	local span = max(1, t1 - t0)
	local r, g, b = T.Color("chart")
	local px, py
	for _, pt in ipairs(points) do
		local x = (pt.t - t0) / span * (w - 4) + 2
		local y = (pt.v - lo) / (hi - lo) * (h - 4) + 2
		if px then
			Eco.ChartLine(c, px, py, x, py, r, g, b)
			Eco.ChartLine(c, x, py, x, y, r, g, b)
		end
		px, py = x, y
	end
	local dot = Eco.ChartTexture(c, "OVERLAY")
	dot:SetColorTexture(r, g, b, 1)
	dot:SetSize(5, 5)
	dot:SetPoint("CENTER", c, "BOTTOMLEFT", px, py)
	Eco.ChartDone(c)
end

local function Show(fig, text, colour, note)
	fig.value:SetText(text)
	fig.value:SetTextColor(T.Color(colour or "ink"))
	fig.fullNote=note or ""
	fig.note:SetText(note or "")
end

function page.Refresh(p)
	local st = DB().settings
	local scope, range = B.Scope(), st.historyRange
	for _, b in ipairs(p.ranges) do
		B.SetOn(b, b.range == range)
	end
	local s = Eco.FortuneSummary(scope, range)
	local rangeLabel = Eco.RANGE_LABEL[range] or range
	-- gold on hand
	if s.gold then
		p.goldValue:SetText(B.Money(s.gold))
		local parts = {}
		for i, ch in ipairs(s.chars) do
			if i <= 4 then
				parts[#parts + 1] = format("%s %s", ch.who, B.Money(ch.money))
			end
		end
		local note = #s.chars > 1 and (format("%d characters, as last seen: ", #s.chars) .. table.concat(parts, ", ")) or ("now, " .. (s.chars[1] and s.chars[1].who or ""))
		p.goldNote:SetText(note); p.goldMetric.fullNote=note
	else
		p.goldValue:SetText("Not enough data")
		p.goldNote:SetText("Your gold is written from this session on: log on each character once.")
	end
	-- history
	local points, info = Eco.GoldSeries(scope, range)
	DrawChart(p, points, info and info.reason)
	if s.change then
		p.change:SetText(format("Balance change over %s: %s", rangeLabel, B.Signed(s.change)))
		p.change:SetTextColor(T.Color(s.change > 0 and "positive" or (s.change < 0 and "negative" or "ink")))
	else
		p.change:SetText(format("Balance change over %s: Not enough data", rangeLabel))
		p.change:SetTextColor(T.Color("uncertain"))
	end
	-- goal
	local goal = Eco.SavingsGoal(scope)
	if goal and s.gold then
		local frac = s.gold / goal
		p.goalBar:SetValue(frac)
		p.goalText:SetText(frac >= 1 and format("Reached: %s of %s", B.Money(s.gold), B.Money(goal))
			or format("%d %% of %s  -  %s to go", floor(frac * 100), B.Money(goal), B.Money(goal - s.gold)))
		p.goalText:SetTextColor(T.Color(frac >= 1 and "positive" or "ink"))
	else
		p.goalBar:SetValue(0)
		p.goalText:SetText(goal and "Your gold is not known yet." or "No goal yet: Set Goal.")
		p.goalText:SetTextColor(T.Color("muted"))
	end
	-- business
	p.rangeNote:SetText("over " .. rangeLabel)
	if s.change then
		Show(p.balance, B.Signed(s.change), s.change > 0 and "positive" or (s.change < 0 and "negative" or "ink"), "everything that moved your gold (not a profit)")
	else
		Show(p.balance, "Not enough data", "uncertain", "the gold history starts with this version")
	end
	Show(p.revenue, B.Money(s.revenue), "ink", format("%d sale%s, the cut taken off", s.sales, s.sales == 1 and "" or "s"))
	if s.profitSales > 0 or s.lost > 0 then
		local note = format("%d sale%s of known cost%s", s.profitSales, s.profitSales == 1 and "" or "s", s.lost > 0 and (", deposits lost " .. B.Money(s.lost)) or "")
		if s.unknownSales > 0 then
			note = note .. format("; Unknown cost: %d sale%s (%s) not counted", s.unknownSales, s.unknownSales == 1 and "" or "s", B.Money(s.unknownRevenue))
		end
		Show(p.profit, B.Signed(s.profit), s.profit >= 0 and "positive" or "negative", note)
        p.profit.note:SetText(format("%d known-cost sales; %d excluded",s.profitSales,s.unknownSales))
	elseif s.unknownSales > 0 then
		Show(p.profit, "Unknown cost", "uncertain", format("%d sale%s whose units were not bought here (not counted as free)", s.unknownSales, s.unknownSales == 1 and "" or "s"))
	else
		Show(p.profit, "Not enough data", "uncertain", "no sale of known cost " .. (range == "session" and "this session" or "in this period"))
	end
	if s.stockItems > 0 then
		Show(p.invested, B.Money(s.invested), "ink", format("%d item%s in stock%s", s.stockItems, s.stockItems == 1 and "" or "s",
			s.unknownUnits > 0 and format("; %d unit%s of Unknown cost", s.unknownUnits, s.unknownUnits == 1 and "" or "s") or ""))
		Show(p.stock, B.Money(s.stockValue), "note", s.noPrice > 0 and format("%d item%s without a price: Not enough data", s.noPrice, s.noPrice == 1 and "" or "s")
			or "After fees; unrealized estimate")
	else
		Show(p.invested, B.Money(0), "muted", "no stock followed")
		Show(p.stock, "-", "muted", "no stock followed")
	end
	-- what to review
	local actions = Eco.ReviewActions(scope)
	for i, b in ipairs(p.actions) do
		local a = actions[i]
		b.action = a
		if a then
			b.stamp:SetKind(a.stamp or "review")
			b.text:SetText(a.text)
			b:Show()
		else
			b:Hide()
		end
	end
	if #actions == 0 then
		p.actions[1].action = nil
		p.actions[1].stamp:SetKind("verified")
		p.actions[1].text:SetText("Nothing waiting: your stock and your prices are up to date.")
		p.actions[1]:Show()
	end
	-- coverage
	if s.ledgers == 0 or not s.ledgerSince then
		p.coverage:SetText("To start: sell or buy at the auction house, then open your mailbox (the mails are read), and post or sell to merchants: each operation is written here. Your gold is followed from this session on.")
	else
		p.coverage:SetText(format("Covered: your trades since %s (auction house mails, merchants, postings), your gold since %s. Not covered: trades with players, loot, quests.",
			date("%m-%d", s.ledgerSince), s.since and date("%m-%d %H:%M", s.since) or "now"))
	end
    p.coverageFull=p.coverage:GetText()
    p.coverage:SetText((s.ledgers==0 or not s.ledgerSince)
        and "To start: open your mailbox after a trade. Hover for tracking details."
        or ("Tracking since "..date("%m-%d",s.ledgerSince)..". Hover for coverage and exclusions."))

end
