--[[
	WC3 Console - economy: the window is The Goblin Ledger (Book.lua and its
	pages, Ledger*.lua). Here: where it opens (beside the auction house, off
	the bags and the console, else where you left it), the scan status, the
	buttons under the auction house, the info bar line, /wc3c eco.
]]

local _, ns = ...
local Eco = ns.Economy
local floor, max, min, format = math.floor, math.max, math.min, string.format
local pairs, ipairs, type, tonumber, tostring = pairs, ipairs, type, tonumber, tostring
local sort = table.sort
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant

local DB, S, BaseID, LinkID = Eco.DB, Eco.S, Eco.BaseID, Eco.LinkID
local Ago, Thousands = Eco.Ago, Eco.Thousands
local Recipes, Category = Eco.Recipes, Eco.Category
local B = Eco.Book

------------------------------------------------------------------------
-- Where the book opens
------------------------------------------------------------------------

local WANT_W, WANT_H, MIN_W, MIN_H = 1180, 760, 1080, 720
local GAP = 10

-- left, bottom, right, top of a shown frame (UIParent units)
local function Rect(frame)
	if not (frame and frame:IsVisible()) then
		return
	end
	local l, b, w, h = frame:GetRect()
	if not l or not w or w <= 0 or h <= 0 then
		return
	end
	local k = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
	return l * k, b * k, (l + w) * k, (b + h) * k
end

-- what the window must not cover (bags, quest tracker, console modules)
local obstacles, count = {}, 0
local function Add(frame)
	local l, b, r, t = Rect(frame)
	if l then
		obstacles[count + 1], obstacles[count + 2], obstacles[count + 3], obstacles[count + 4] = l, b, r, t
		count = count + 4
	end
end

local function Obstacles()
	count = 0
	Add(_G.ContainerFrameCombinedBags)
	for i = 1, (_G.NUM_CONTAINER_FRAMES or 13) do
		Add(_G["ContainerFrame" .. i])
	end
	Add(_G.ObjectiveTrackerFrame)
	for _, m in ipairs(ns.modules) do
		if m.frame and m.key ~= "infobar" then
			Add(m.frame)
		end
	end
end

-- where you left it (its size too), else right of the auction house (or
-- where it opens), down to the top of the bags / console, as big as the
-- room allows (in the book's own scale)
function Eco.Place(force)
	local f = Eco.frame
	if not f or f.moving then
		return
	end
	local e = DB()
	local scale = f:GetScale() or 1
	local sw, sh = UIParent:GetWidth() / scale, UIParent:GetHeight() / scale
	local left, top, width, height
	if e.pos then
		left, top, width, height = e.pos.x, e.pos.y, e.pos.w or WANT_W, e.pos.h or WANT_H
	else
		local topLimit = sh - 6
		local ib = ns.moduleByKey.infobar
		local _, ibBottom = Rect(ib and ib.frame)
		if ibBottom and ibBottom / scale > sh / 2 then
			topLimit = ibBottom / scale - 6
		end
		local _, _, ahRight, ahTop = Rect(_G.AuctionHouseFrame)
		if ahRight then
			left, top = ahRight / scale + GAP + 4, min(ahTop / scale, topLimit - 10)
		else
			left, top = 16, min(topLimit - 60, sh - 104)
		end
		Obstacles()
		local right = min(sw - GAP, left + WANT_W)
		for i = 1, count, 4 do
			local l, b, t = obstacles[i] / scale, obstacles[i + 1] / scale, obstacles[i + 3] / scale
			if l > left + 60 and l < right and t > top - MIN_H and b < top then
				right = l - GAP
			end
		end
		width = max(MIN_W, right - left)
		local bottom = GAP
		for i = 1, count, 4 do
			local l, r, t = obstacles[i] / scale, obstacles[i + 2] / scale, obstacles[i + 3] / scale
			if l < left + width and r > left and t <= top then
				bottom = max(bottom, t + GAP)
			end
		end
		height = max(MIN_H, min(WANT_H, top - bottom))
		-- Preserve the layout's logical minimum; fit the whole window when
		-- the auction house and open bags leave less vertical space.
		if top - bottom < MIN_H or right - left < MIN_W then
			local fit = min(1, (sw - left - GAP) / WANT_W, (top - bottom) / WANT_H)
			if fit > 0 and scale * fit >= 0.7 then
				scale = scale * fit
				f:SetScale(scale)
				left, top = left / fit, top / fit
				sw, sh = sw / fit, sh / fit
				width, height = WANT_W, WANT_H
			end
		end
		-- (no room beside the auction house: over it, the book is wide)
		if left + width > sw then
			left = max(0, sw - width - GAP)
		end
	end
	-- (always on the screen, whatever the scale since it was placed)
	width, height = min(width, sw), min(height, sh)
	left = max(0, min(left, sw - width))
	top = min(sh, max(top, height))
	left, top, width, height = floor(left), floor(top), floor(width), floor(height)
	if not force and f.placed and f.placed[1] == left and f.placed[2] == top and f.placed[3] == width and f.placed[4] == height then
		return
	end
	f.placed = { left, top, width, height }
	f:ClearAllPoints()
	f:SetSize(width, height)
	f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

------------------------------------------------------------------------
-- Open, close, draw again
------------------------------------------------------------------------

function Eco.Toggle()
	local f = B.Create()
	f:SetShown(not f:IsShown())
end

-- open a page (and a method of Make Gold, a view of My Business)
function Eco.OpenLedger(pageKey, sub)
	local f = B.Create()
	local st = DB().settings
	if pageKey == "gold" and sub then
		st.goldMethod = sub
	elseif pageKey == "business" and sub then
		st.businessView = sub
	end
	B.state.page = pageKey
	if not f:IsShown() then
		f:Show()
	else
		B.Open(pageKey)
	end
end

-- (the tabs of the window before the ledger: their pages now)
local OLD_TABS = { market = { "market" }, deals = { "gold", "resell" }, crafts = { "gold", "craft" }, enchant = { "gold", "de" },
	synergy = { "gold", "craftde" }, trades = { "business", "journal" } }
function Eco.SelectTab(tab)
	local t = OLD_TABS[tab] or { "overview" }
	Eco.OpenLedger(t[1], t[2])
end

function Eco.Refresh()
	if B.frame then
		B.Refresh()
		Eco.UpdateStatus()
	end
end

-- the status of the scans, short (the header) and long (its tooltip)
local function ScanStatus(long)
	local _, r = DB()
	if S.state == "decheck" then
        return "Checking auction..."
	elseif S.state == "waiting" then
		return "Full scan: waiting for the server..."
	elseif S.state == "reading" then
		return format("Full scan: reading %d%%", floor(S.progress * 100))
	elseif S.state == "saving" then
		return format("Saving the prices %d%%", floor(S.progress * 100))
	elseif S.state == "browse" then
		return format("Quick scan: page %d...", S.pages or 0)
	elseif r.lastScan then
		if long then
			local size = r.lastMode == "full" and (Thousands(r.lastAuctions or 0) .. " auctions") or (Thousands(r.lastItems or 0) .. " items")
			local text = format("Last scan %s: %s, %s.", Ago(r.lastScan), r.lastMode or "?", size)
			if r.lastMode == "quick" then
				text = text .. format(" A quick scan sees the lowest price and the total of each item; the last full scan was %s.", Ago(r.fullAt))
			end
			local full, wait = Eco.CanFullScan()
			text = text .. (full and " A full scan is possible now." or format(" Full scan again in %d min.", math.ceil(wait / 60)))
			return text
		end
		return format("Scanned %s (%s)", Ago(r.lastScan), r.lastMode or "?")
	end
	return "No scan yet"
end

function Eco.ScanStatusLong()
	return ScanStatus(true) .. (Eco.AuctionHouseOpen() and "" or " Open the auction house to scan.")
end

function Eco.UpdateStatus()
	if not ns.db then
		return
	end
	local label
	if S.state ~= "idle" then
		label = S.state == "reading" and format("Scan %d%%", floor(S.progress * 100)) or "Scanning..."
	else
		label = Eco.CanFullScan() and "Scan (full)" or "Scan (quick)"
	end
	local open = Eco.AuctionHouseOpen()
	for _, b in ipairs(Eco.scanButtons) do
		b:SetText(label)
		b:SetEnabled(S.state == "idle" and open)
	end
	if Eco.frame and Eco.frame.status then
		Eco.frame.status:SetText(ScanStatus(false))
	end
end

-- item infos arriving: the book shows their names, prices...
local refreshPending = false
ns.On("GET_ITEM_INFO_RECEIVED", function()
	if refreshPending or not (Eco.frame and Eco.frame:IsShown()) or S.state ~= "idle" then
		return
	end
	refreshPending = true
	C_Timer.After(1, function()
		refreshPending = false
		Eco.Refresh()
	end)
end)

-- the fortune shown changes with the gold
ns.On("PLAYER_MONEY", function()
	if Eco.frame and Eco.frame:IsShown() and B.state.page == "overview" then
		Eco.Refresh()
	end
end)

------------------------------------------------------------------------
-- Auction house: The Goblin Ledger and Scan buttons under its frame
------------------------------------------------------------------------

local function HookAuctionHouse()
	local ah = _G.AuctionHouseFrame
	if not ah or Eco.ahHooked then
		return
	end
	Eco.ahHooked = true
	local scan = CreateFrame("Button", nil, ah, "UIPanelButtonTemplate")
	scan:SetSize(120, 22)
	scan:SetPoint("TOPRIGHT", ah, "BOTTOMRIGHT", -4, -2)
	scan:SetScript("OnClick", Eco.Scan)
	scan:SetScript("OnEnter", Eco.View.ScanTooltip)
	scan:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	Eco.scanButtons[#Eco.scanButtons + 1] = scan
	local open = CreateFrame("Button", nil, ah, "UIPanelButtonTemplate")
	open:SetSize(124, 22)
	open:SetPoint("RIGHT", scan, "LEFT", -4, 0)
	open:SetText("Goblin Ledger")
	open:SetScript("OnClick", Eco.Toggle)
	Eco.UpdateStatus()
end

ns.On("ADDON_LOADED", function(_, name)
	if name == "Blizzard_AuctionHouseUI" then
		C_Timer.After(0, HookAuctionHouse)
	end
end)

ns.On("AUCTION_HOUSE_SHOW", function()
	-- now: the auctioneer is the "npc" unit while the auction house is open
	ns.Try("economy market", Eco.OpenMarket)
	C_Timer.After(0, function()
		HookAuctionHouse()
		Eco.UpdateStatus()
	end)
end)

------------------------------------------------------------------------
-- Info bar tooltip, slash command
------------------------------------------------------------------------

function Eco.TooltipLines(tt)
	if not ns.db then
		return
	end
	local _, r = DB()
	tt:AddDoubleLine("Last auction scan", Ago(r.lastScan), 1, 0.82, 0, 1, 1, 1)
end

function Eco.Slash(rest)
	rest = (rest or ""):lower()
	if rest == "reset" then
		DB().pos = nil
		if Eco.frame then
			Eco.Place(true)
		end
		ns.Print("The Goblin Ledger: automatic placement.")
	elseif rest == "scan" then
		Eco.Scan()
	elseif rest == "textures" then
		Eco.Theme.Report()
	elseif rest:match("^theme") then
		local key = rest:match("^theme%s+(%S+)")
		if key and Eco.Theme.THEMES[key] then
			B.Create()
			B.SetTheme(key)
			ns.Print("theme: " .. Eco.Theme.THEMES[key].label)
		else
			ns.Print("/wc3c eco theme merchant | bilgewater | prince")
		end
    elseif rest:match("^de exclude ") then
        local id=tonumber(rest:match("^de exclude (%d+)"));if id then Eco.DEExclude(id,true) end
    elseif rest:match("^de allow ") then
        local id=tonumber(rest:match("^de allow (%d+)"));if id then Eco.DEExclude(id,false) end
    elseif rest:match("^de terms") then
        Eco.DESetExclusionTerms(rest:match("^de terms%s*(.*)$"))
        ns.Print("DE exclusions updated: name or stat text, comma separated.")
	elseif rest == "de" or rest:match("^de%s") then
		-- can this item be disenchanted, and by whom (an id or a shift-clicked link)
		Eco.DEExplain(rest:match("^de%s+(.+)$"))
	elseif rest:match("^class ") then
		local ref = rest:match("^class%s+(.+)$")
		local id = tonumber(ref) or LinkID(ref)
		if id then
			local _, _, _, _, _, class, sub = GetItemInfoInstant(id)
			local cat, s = Category(id)
			ns.Print(format("item %d: class %s, subclass %s -> %s", id, tostring(class), tostring(sub), Eco.CategoryLabel(cat, s)))
		end
	elseif rest == "classify" then
		local _, r = DB()
		local counted, others = {}, {}
		for key, rec in pairs(r.items) do
			if rec.s == r.scanId then
				local id = BaseID(key)
				local cat, s = Category(id)
				local label = Eco.CategoryLabel(cat, s)
				counted[label] = (counted[label] or 0) + 1
				if cat == "other" or s == "other" then
					local _, _, _, _, _, class, sub = GetItemInfoInstant(id)
					others[#others + 1] = format("%d (%s/%s)", id, tostring(class), tostring(sub))
				end
			end
		end
		local labels = {}
		for label, n in pairs(counted) do
			labels[#labels + 1] = label .. " " .. n
		end
		sort(labels)
		ns.Print("items of the last scan by category: " .. table.concat(labels, ", "))
		sort(others)
		ns.Print("in an \"other\" group (id, class/subclass), first 30: " .. table.concat(others, ", ", 1, min(30, #others)))
	elseif rest == "purge" then
		ns.Print("erase the prices of |cffffffff" .. Eco.MarketLabel() .. "|r (history, supply)? Type |cffffffff/wc3c eco purge confirm|r. Your trades are kept.")
	elseif rest == "purge confirm" then
		local label = Eco.MarketLabel()
		Eco.Purge()
		ns.Print("prices of |cffffffff" .. label .. "|r erased.")
	elseif rest == "debug" then
		local e, r = DB()
		local n, rc, v = 0, 0, 0
		for _ in pairs(r.items) do
			n = n + 1
		end
		for _, list in pairs(Recipes()) do
			for _ in pairs(list) do
				rc = rc + 1
			end
		end
		for _ in pairs(e.vendor) do
			v = v + 1
		end
		local T = C_TradeSkillUI
		ns.Print(format("market %s (cut %d%%) | items %d, recipes %d, vendor prices %d | full scan API %s, quick scan API %s, recipes API %s | ledgers %d",
			Eco.market.key, floor(Eco.cut * 100 + 0.5), n, rc, v,
			tostring(C_AuctionHouse ~= nil and C_AuctionHouse.ReplicateItems ~= nil),
			tostring(C_AuctionHouse ~= nil and C_AuctionHouse.GetBrowseResults ~= nil),
			(T and T.GetRecipeSchematic and "modern") or (GetNumTradeSkills and "legacy") or "none", #Eco.Ledgers("all")))
	else
		Eco.Toggle()
	end
end
