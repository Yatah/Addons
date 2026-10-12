--[[
	WC3 Console - economy: what the lists show, their columns and tooltips
]]

local _, ns = ...
local Eco = ns.Economy
local floor, ceil, format = math.floor, math.ceil, string.format
local ipairs, tostring = ipairs, tostring

local DB, Item, BaseID, Icon, QualityColor = Eco.DB, Eco.Item, Eco.BaseID, Eco.Icon, Eco.QualityColor
local Money, ProfitText, Thousands = Eco.Money, Eco.ProfitText, Eco.Thousands
local STATUS, KINDS, SUPPLY_FALLING, MaterialValue = Eco.STATUS, Eco.KINDS, Eco.SUPPLY_FALLING, Eco.MaterialValue
local HOUR, DAY = Eco.HOUR, Eco.DAY

------------------------------------------------------------------------
-- Columns
------------------------------------------------------------------------

local function ItemOf(d)
	return (d.link and Item(d.link)) or Item(d.id)
end

local function NameText(d)
	local it = ItemOf(d)
	local extra = (d.made and d.made ~= 1) and format(" |cffffffffx%s|r", d.made) or ""
	if it then
		local r, g, b = QualityColor(it.quality)
		return it.name .. extra, r, g, b
	end
	return "item " .. tostring(d.id) .. extra, 0.6, 0.6, 0.6
end

local function NameSort(d)
	local it = ItemOf(d)
	return it and it.name:lower()
end

local function IconOf(d)
	return Icon(d.id)
end

-- days of history: under 7 grey (tests only), 7-13 yellow, 14 and more white
local function DaysText(d)
	local n = d.days or 0
	if n < 7 then
		return tostring(n), 0.6, 0.6, 0.6
	elseif n < 14 then
		return tostring(n), 1, 0.82, 0
	end
	return tostring(n), 1, 1, 1
end

local function Age(sec)
	if not sec then
		return "-"
	elseif sec < HOUR then
		return format("%dm", floor(sec / 60))
	elseif sec < DAY then
		return format("%dh", floor(sec / HOUR))
	end
	return format("%dd %dh", floor(sec / DAY), floor(sec % DAY / HOUR))
end

local function Pct(x, signed)
	if not x then
		return "-"
	end
	local v = floor(x * 100 + 0.5)
	return format(signed and "%+d%%" or "%d%%", v)
end

local COLUMNS = {}

COLUMNS.deals = {
	{ label = "Item", width = 0, icon = IconOf, text = NameText, sort = NameSort, desc = false },
	{ label = "Status", width = 62, text = function(d)
		local s = STATUS[d.status]
		return s[1], s[2], s[3], s[4]
	end, sort = function(d)
		return STATUS[d.status][5]
	end },
	{ label = "Price", width = 76, align = "RIGHT", text = function(d)
		return Money(d.price)
	end, sort = function(d)
		return d.price
	end },
	{ label = "Max buy", width = 76, align = "RIGHT", text = function(d)
		return Money(d.maxBuy), 1, 0.82, 0
	end, sort = function(d)
		return d.maxBuy
	end },
	-- units to buy now / units under the max buy price
	{ label = "Buy", width = 48, align = "RIGHT", text = function(d)
		if d.buy == 0 then
			return "0/" .. d.units, 1, 0.35, 0.35
		end
		return d.buy .. "/" .. d.units
	end, sort = function(d)
		return d.buy
	end },
	{ label = "Cost", width = 76, align = "RIGHT", text = function(d)
		if d.buy == 0 then
			return "-", 0.6, 0.6, 0.6
		end
		return Money(d.cost)
	end, sort = function(d)
		return d.cost
	end },
	{ label = "Resell", width = 76, align = "RIGHT", text = function(d)
		return Money(d.resell)
	end, sort = function(d)
		return d.resell
	end },
	-- profit of what you can buy now; in grey: all the units under the max
	{ label = "Profit", width = 80, align = "RIGHT", text = function(d)
		if d.buy == 0 then
			return "|cff808080(" .. Money(d.potential) .. ")|r"
		end
		return ProfitText(d.profit)
	end, sort = function(d)
		return d.buy > 0 and 1e12 + d.profit or d.potential
	end },
	{ label = "Days", width = 34, align = "RIGHT", text = DaysText, sort = function(d)
		return d.days
	end },
}

COLUMNS.trades = {
	{ label = "Item", width = 0, icon = IconOf, text = NameText, sort = NameSort, desc = false },
	{ label = "Stock", width = 44, align = "RIGHT", text = function(d)
		return tostring(d.stock)
	end, sort = function(d)
		return d.stock
	end },
	{ label = "Age", width = 54, align = "RIGHT", text = function(d)
		return Age(d.age)
	end, sort = function(d)
		return d.age or -1
	end },
	{ label = "Stock cost", width = 76, align = "RIGHT", text = function(d)
		return Money(d.stockCost)
	end, sort = function(d)
		return d.stockCost
	end },
	{ label = "Sold 7d", width = 50, align = "RIGHT", text = function(d)
		return tostring(d.sold7)
	end, sort = function(d)
		return d.sold7
	end },
	-- units sold within 48 h of their purchase
	{ label = "48 h", width = 44, align = "RIGHT", text = function(d)
		local v = d.sellThrough
		if not v then
			return "-", 0.6, 0.6, 0.6
		end
		return Pct(v), v >= 0.7 and 0.3 or 1, v >= 0.7 and 1 or (v < 0.3 and 0.35 or 0.82), v >= 0.7 and 0.3 or (v < 0.3 and 0.35 or 0)
	end, sort = function(d)
		return d.sellThrough
	end },
	{ label = "Avg sale", width = 76, align = "RIGHT", text = function(d)
		return Money(d.avgSale)
	end, sort = function(d)
		return d.avgSale
	end },
	{ label = "Profit", width = 80, align = "RIGHT", text = function(d)
		return ProfitText(d.profit)
	end, sort = function(d)
		return d.profit
	end },
	{ label = "Advice", width = 110, text = function(d)
		return d.advice, d.adviceColor[1], d.adviceColor[2], d.adviceColor[3]
	end, sort = function(d)
		return d.advice
	end },
}

local CONFIDENCE = { { "Low", 0.6, 0.6, 0.6 }, { "Medium", 1, 0.82, 0 }, { "High", 0.3, 1, 0.3 } }
local STAR = "|A:auctionhouse-icon-favorite:13:13|a "

local function SignedText(x, r, g, b)
	if not x then
		return "-", 0.6, 0.6, 0.6
	end
	return format("%+d%%", floor(x * 100 + 0.5)), r or 1, g or 1, b or 1
end

COLUMNS.market = {
	{ label = "Item", width = 0, icon = IconOf, text = function(d)
		local text, r, g, b = NameText(d)
		return (d.watched and STAR or "") .. text, r, g, b
	end, sort = NameSort, desc = false },
	{ label = "Price", width = 76, align = "RIGHT", text = function(d)
		return Money(d.price)
	end, sort = function(d)
		return d.price
	end },
	-- 3 days against 14
	{ label = "Price trend", width = 64, align = "RIGHT", text = function(d)
		local down = d.trend and d.trend < -0.1
		return SignedText(d.trend, 1, down and 0.35 or 1, down and 0.35 or 1)
	end, sort = function(d)
		return d.trend
	end },
	{ label = "Listed", width = 56, align = "RIGHT", text = function(d)
		return Thousands(d.listed)
	end, sort = function(d)
		return d.listed
	end },
	-- listed quantity, 3 days against 14
	{ label = "Supply", width = 56, align = "RIGHT", text = function(d)
		local low = d.supply and d.supply <= SUPPLY_FALLING
		return SignedText(d.supply, 1, low and 0.82 or 1, low and 0 or 1)
	end, sort = function(d)
		return d.supply
	end, desc = false },
	-- listed now against the usual quantity at this time of day
	{ label = "Now/usual", width = 66, align = "RIGHT", text = function(d)
		return SignedText(d.now)
	end, sort = function(d)
		return d.now
	end },
	{ label = "My sales/d", width = 64, align = "RIGHT", text = function(d)
		if not d.velocity or d.velocity == 0 then
			return "-", 0.6, 0.6, 0.6
		end
		return format("%.1f", d.velocity)
	end, sort = function(d)
		return d.velocity
	end },
	{ label = "Confidence", width = 72, text = function(d)
		local c = CONFIDENCE[d.confidence]
		return c[1], c[2], c[3], c[4]
	end, sort = function(d)
		return d.confidence
	end },
}

COLUMNS.journal = {
	{ label = "When", width = 84, text = function(d)
		return date("%m-%d %H:%M", d.t), 0.8, 0.8, 0.8
	end, sort = function(d)
		return d.t
	end },
	{ label = "Type", width = 104, text = function(d)
		local k = KINDS[d.kind]
		return k[1], k[2], k[3], k[4]
	end, sort = function(d)
		return d.kind
	end },
	{ label = "Item", width = 0, icon = IconOf, text = NameText, sort = NameSort, desc = false },
	{ label = "Qty", width = 40, align = "RIGHT", text = function(d)
		return tostring(d.q)
	end, sort = function(d)
		return d.q
	end },
	-- gold in / out
	{ label = "Gold", width = 84, align = "RIGHT", text = function(d)
		if not d.gold then
			return "-", 0.6, 0.6, 0.6
		end
		return (d.gold > 0 and "+" or "") .. ProfitText(d.gold)
	end, sort = function(d)
		return d.gold
	end },
	{ label = "Profit", width = 84, align = "RIGHT", text = function(d)
		if not d.profit then
			return "-", 0.6, 0.6, 0.6
		end
		return ProfitText(d.profit)
	end, sort = function(d)
		return d.profit
	end },
}

COLUMNS.crafts = {
	{ label = "Product", width = 0, icon = IconOf, text = NameText, sort = NameSort, desc = false },
	{ label = "Cost", width = 80, align = "RIGHT", text = function(d)
		return Money(d.cost)
	end, sort = function(d)
		return d.cost
	end },
	{ label = "Sale - cut", width = 80, align = "RIGHT", text = function(d)
		return Money(d.net)
	end, sort = function(d)
		return d.net
	end },
	{ label = "Profit", width = 80, align = "RIGHT", text = function(d)
		return ProfitText(d.profit)
	end, sort = function(d)
		return d.profit
	end },
	{ label = "Margin", width = 50, align = "RIGHT", text = function(d)
		if not d.margin then
			return "-", 0.6, 0.6, 0.6
		end
		return format("%d%%", floor(d.margin * 100))
	end, sort = function(d)
		return d.margin
	end },
	{ label = "Listed", width = 46, align = "RIGHT", text = function(d)
		return tostring(d.listed or 0)
	end, sort = function(d)
		return d.listed
	end },
}

-- (a lot not to buy: an estimate, not safe enough, out of the plan; greyed)
local function LotText(d, text)
	if not d.cost then
		return "-", 0.6, 0.6, 0.6
	elseif not d.ok then
		return text, 0.6, 0.6, 0.6
	end
	return text
end

-- why a lot is advised or not (Eco.ComputeEnchant: d.status)
local DE_STATUS = {
	advised = { "Advised", 0.3, 1, 0.3, 5, "Confirmed items, an enchanter of yours, a yield table validated on this client, the chance and the profit asked for." },
	estimate = { "Estimate", 1, 0.82, 0, 4, "Model-based lot using classic probabilities. These yields are not validated on this server; profit is an estimate." },
	unsafe = { "Not safe", 1, 0.5, 0.2, 3, "Under the chance or the profit asked for." },
	outside = { "Out of plan", 1, 0.5, 0.2, 2, "Your capital went to better returns." },
	excluded = { "Excluded", 1, 0.35, 0.35, 1, "No item of this lot is both confirmed by the game and disenchantable by an enchanter of yours (the reasons: tooltip)." },
	none = { "-", 0.6, 0.6, 0.6, 0, "No auction at the max price or under." },
}
Eco.DE_STATUS = DE_STATUS

COLUMNS.enchant = {
	{ label = "Lot", width = 0, icon = function(d)
		return Icon(d.icon)
	end, text = function(d)
		local r, g, b = QualityColor(d.quality)
		return d.label, r, g, b
	end, sort = function(d)
		return d.order
	end, desc = false,
		tip = "Gear that disenchants alike in the classic tables: its quality and item level (armor or weapon for the uncommon ones). Only the items the game confirmed as disenchantable, that an enchanter of yours can disenchant, count in it." },
	{ label = "Status", width = 64, text = function(d)
		local s = DE_STATUS[d.status] or DE_STATUS.none
		return s[1], s[2], s[3], s[4]
	end, sort = function(d)
		return (DE_STATUS[d.status] or DE_STATUS.none)[5]
	end, tip = "Advised: to buy. Estimate: yield table not validated on this client, no advice. Not safe / Out of plan: under what you asked for. Excluded: no confirmed item an enchanter of yours can disenchant." },
	-- the mean of one disenchant (* a material without a price)
	{ label = "DE value", width = 72, align = "RIGHT", text = function(d)
		return Money(d.mean) .. (d.missing and "|cffff8040*|r" or "")
	end, sort = function(d)
		return d.mean
	end, tip = "Estimate of what one disenchant brings on average: each material the yield table gives, by its chance and its quantity, sold at the auction house price of the last scan (the lowest, never above the usual one), its cut (5 %, 15 % at a neutral one) taken off. Paying this much for an item: no profit on average. |cffff8040*|r: a material without a price (counted 0)." },
	-- the threshold: the mean less the return asked for
	{ label = "Max price", width = 72, align = "RIGHT", text = function(d)
		if not d.most or d.most <= 0 then
			return "-", 0.6, 0.6, 0.6
		end
		return Money(d.most), 1, 0.82, 0
	end, sort = function(d)
		return d.most
	end, tip = "The most to pay for one item: DE value / (1 + the return asked for). Your threshold at the auction house: above it, skip." },
	-- auctions of confirmed items with the return asked for, seen in the
	-- last scan (maybe bought since)
	{ label = "Seen", width = 50, align = "RIGHT", text = function(d)
		if d.available == 0 then
			return "0", 0.6, 0.6, 0.6
		end
		return tostring(d.available)
	end, sort = function(d)
		return d.available
	end, tip = "Units of confirmed items at the max price or under, seen in the last scan: they may have been bought since. A quick scan sees the cheapest auction of each item only. The items left out (forbidden, not known, no enchanter) are not counted: tooltip." },
	{ label = "To buy", width = 50, align = "RIGHT", text = function(d)
		if not d.buy then
			return "-", 0.6, 0.6, 0.6
		elseif not d.ok then
			return tostring(d.buy), 0.6, 0.6, 0.6
		end
		return tostring(d.buy), 0.3, 1, 0.3
	end, sort = function(d)
		return d.buy
	end, desc = false,
		tip = "Without a capital: the fewest of them, cheapest first, for the chance of a profit asked for (more of them make the lot safer still). With a capital: what its plan buys of this lot." },
	{ label = "Avg price", width = 70, align = "RIGHT", text = function(d)
		return LotText(d, Money(d.avg))
	end, sort = function(d)
		return d.avg
	end, tip = "The mean price of the items to buy: the price the line is computed on (each one in the tooltip of the lot)." },
	{ label = "Cost", width = 72, align = "RIGHT", text = function(d)
		return LotText(d, Money(d.cost))
	end, sort = function(d)
		return d.cost
	end, tip = "What the items to buy cost in all." },
	{ label = "Profit", width = 72, align = "RIGHT", text = function(d)
		if d.ok then
			return ProfitText(d.profit)
		end
		return LotText(d, d.profit and Money(d.profit))
	end, sort = function(d)
		return d.profit
	end, tip = "Expected: items to buy x DE value - cost." },
	-- expected profit / cost
	{ label = "Return", width = 52, align = "RIGHT", text = function(d)
		if d.ok and d.ret then
			return Pct(d.ret), 0.3, 1, 0.3
		end
		return LotText(d, Pct(d.ret))
	end, sort = function(d)
		return d.ret
	end, tip = "Expected profit / cost." },
	{ label = "Model", width = 52, align = "RIGHT", text = function(d)
		local text = d.chance and format("%d%%", floor(d.chance * 100))
		if not text then
			return "-", 0.6, 0.6, 0.6
		elseif not d.ok then
			return text, 0.6, 0.6, 0.6
		elseif d.chance >= d.target then
			return text, 0.3, 1, 0.3
		elseif d.planned then
			return text -- (the plan as a whole is what counts: under the list)
		end
		return text, 1, 0.5, 0.2
	end, sort = function(d)
		return d.chance
	end, tip = "The chance of a profit computed by the model, under its assumptions: the yield table, the prices of the last scan, every auction still there. Not a guarantee. With a capital, the chance of the whole plan (under the list) is what counts." },
}

-- Synergy: what brings the most for a product
local OUTLET = { de = "|cffc080ffDE|r", ah = "|cffffffffAH|r", vendor = "|cff40ff40vendor|r" }
local COLOUR = { [0] = { "orange", 1, 0.5, 0.25 }, [1] = { "yellow", 1, 1, 0 }, [2] = { "green", 0.25, 0.8, 0.25 } }

-- (a craft not to make: not profitable, not safe enough, beyond the capital; greyed)
local function CraftText(d, text)
	if not d.ok then
		return text, 0.6, 0.6, 0.6
	end
	return text
end

local function ByText(d)
	return d.crafter.who
end

COLUMNS.gold = {
	{ label = "Product", width = 0, icon = IconOf, text = NameText, sort = NameSort, desc = false,
		tip = "A craft of your account to disenchant (uncommon gear and better): craft it, disenchant it, sell the materials." },
	{ label = "By", width = 70, text = ByText, sort = ByText, desc = false, tip = "The character who crafts it." },
	{ label = "Cost / craft", width = 76, align = "RIGHT", text = function(d)
		return Money(d.one)
	end, sort = function(d)
		return d.one
	end, tip = "The materials of one craft, the cheapest way: auction house, vendor or crafted (? : not all of them to be had)." },
	{ label = "DE value", width = 76, align = "RIGHT", text = function(d)
		if d.o.state ~= "ok" then
			return "-", 0.6, 0.6, 0.6 -- (not confirmed as disenchantable: tooltip)
		elseif not d.o.de then
			return Money(d.value), 0.6, 0.6, 0.6
		end
		return Money(d.value)
	end, sort = function(d)
		return d.o.de and d.value or 0
	end, tip = "Estimate of what one craft brings disenchanted: the mean of its materials (yield table) sold at the auction house, its cut taken off. -: the game did not confirm the product can be disenchanted; grey: no enchanter of yours can (the tooltip says why)." },
	{ label = "Crafts", width = 48, align = "RIGHT", text = function(d)
		if not d.crafts then
			return "-", 0.6, 0.6, 0.6
		end
		return CraftText(d, tostring(d.crafts))
	end, sort = function(d)
		return d.crafts
	end, tip = "Without a capital: the fewest crafts for the chance asked for. With one: as many as stay profitable (the cheap materials go first) within it, with that chance." },
	{ label = "Cost", width = 76, align = "RIGHT", text = function(d)
		return CraftText(d, Money(d.cost))
	end, sort = function(d)
		return d.cost
	end, tip = "The materials of these crafts: the shopping list in the tooltip." },
	{ label = "Profit", width = 76, align = "RIGHT", text = function(d)
		if d.ok then
			return ProfitText(d.profit)
		end
		return CraftText(d, Money(d.profit))
	end, sort = function(d)
		return d.profit
	end, tip = "Expected: crafts x DE value - their cost." },
	{ label = "Return", width = 50, align = "RIGHT", text = function(d)
		if d.ok and d.ret then
			return Pct(d.ret), 0.3, 1, 0.3
		end
		return CraftText(d, Pct(d.ret))
	end, sort = function(d)
		return d.ret
	end, tip = "Expected profit / cost." },
	{ label = "Model", width = 50, align = "RIGHT", text = function(d)
		if not d.chance then
			return "-", 0.6, 0.6, 0.6
		end
		local text = format("%d%%", floor(d.chance * 100))
		if not d.ok then
			return text, 0.6, 0.6, 0.6
		elseif d.chance >= d.target then
			return text, 0.3, 1, 0.3
		end
		return text, 1, 0.5, 0.2
	end, sort = function(d)
		return d.chance
	end, tip = "The chance of a profit computed by the model (a disenchant gives its materials by chance), under its assumptions: the yield table, the prices of the last scan. Not a guarantee; grey: an estimate (table not validated on this client) or not safe enough." },
}

COLUMNS.level = {
	{ label = "Product", width = 0, icon = IconOf, text = NameText, sort = NameSort, desc = false,
		tip = "A recipe that still gives skill points (the grey ones are left out)." },
	{ label = "By", width = 70, text = ByText, sort = ByText, desc = false, tip = "The character who crafts it." },
	{ label = "Colour", width = 56, text = function(d)
		local c = COLOUR[d.color]
		if not c then
			return "?", 0.6, 0.6, 0.6
		end
		return c[1], c[2], c[3], c[4]
	end, sort = function(d)
		return d.color
	end, desc = false,
		tip = "Its colour at the rank its window was seen: orange, a point each craft; yellow, most of the time; green, now and then; grey, never. ? : open the profession window once more." },
	{ label = "Point", width = 44, align = "RIGHT", text = function(d)
		if not d.points then
			return "?", 0.6, 0.6, 0.6
		end
		return format("%d%%", floor(d.points * 100 + 0.5))
	end, sort = function(d)
		return d.points
	end, tip = "Chance of a skill point by craft, from its colour (estimated: green near grey gives less)." },
	{ label = "Cost", width = 70, align = "RIGHT", text = function(d)
		return Money(d.one)
	end, sort = function(d)
		return d.one
	end, tip = "The materials of one craft, the cheapest way (? : not all of them to be had)." },
	{ label = "Brings back", width = 92, align = "RIGHT", text = function(d)
		return Money(d.back) .. " " .. (d.o and OUTLET[d.o.outlet] or "")
	end, sort = function(d)
		return d.back
	end, tip = "What the product brings back: disenchanted (by an enchanter of your account), the materials sold; else to a vendor." },
	{ label = "Net", width = 70, align = "RIGHT", text = function(d)
		return ProfitText(d.net and -d.net)
	end, sort = function(d)
		return d.net and -d.net
	end, tip = "What one craft costs once its product sold (green: it pays)." },
	{ label = "Per point", width = 74, align = "RIGHT", text = function(d)
		return ProfitText(d.perPoint and -d.perPoint)
	end, sort = function(d)
		return d.perPoint
	end, desc = false, tip = "What a skill point costs: the net of a craft / its chance of a point (green: it pays)." },
	{ label = "Can make", width = 60, align = "RIGHT", text = function(d)
		if not d.can or d.can == 0 then
			return "0", 1, 0.5, 0.2
		end
		return d.can >= 100 and "100+" or tostring(d.can)
	end, sort = function(d)
		return d.can
	end, tip = "Crafts the materials to be had now allow." },
}

------------------------------------------------------------------------
-- Tooltips
------------------------------------------------------------------------

local function ItemTooltip(owner, d)
	local tt = GameTooltip
	tt:SetOwner(owner, "ANCHOR_RIGHT")
	local link = d.link or ("item:" .. tostring(d.id))
	if not pcall(tt.SetHyperlink, tt, link) then
		tt:AddLine(NameText(d))
	end
	return tt
end

local function Line(tt, left, right, r, g, b)
	tt:AddDoubleLine(left, right, 1, 0.82, 0, r or 1, g or 1, b or 1)
end

local function DealTooltip(row, d)
	local tt = ItemTooltip(row, d)
	local status = STATUS[d.status]
	tt:AddLine(" ")
	Line(tt, "Status", status[1], status[2], status[3], status[4])
	Line(tt, "Category", Eco.CategoryLabel(d.cat, d.sub))
	Line(tt, "Lowest price", Money(d.price) .. "  (" .. Thousands(d.listed) .. " listed)")
	if d.status == "vendor" then
		Line(tt, "Vendor price", Money(d.resell))
		tt:AddLine("Below the vendor price: sell it to a vendor, a sure profit.", 0.3, 1, 0.3, true)
		tt:AddLine("Click: search it at the auction house", 0.5, 0.8, 1)
		tt:Show()
		return
	end
	local i = d.ind
	tt:AddLine(Eco.ContextLine(i), 0.8, 0.8, 0.8)
	local depth = (d.days < 7 and "tests only") or (d.days < 14 and "limited") or (d.days < 28 and "base") or "reference"
	Line(tt, "History", d.days .. " days (" .. depth .. ")")
	Line(tt, "M3 / M14", Money(i.m3) .. " / " .. Money(i.m14))
	local falling = i.trend and i.trend < -0.1
	Line(tt, "Trend M3 / M14 - 1", Pct(i.trend, true), falling and 1 or 1, falling and 0.35 or 1, falling and 0.35 or 1)
	Line(tt, "Q25 of 7 days", Money(i.q25_7))
	Line(tt, "Q25 / Q75 of 14 days", Money(i.q25) .. " / " .. Money(i.q75))
	Line(tt, "Spread (Q75 - Q25) / M14", Pct(i.spread))
	if not d.exact then
		Line(tt, "Price left after buying", "unknown (full scan needed)", 0.6, 0.6, 0.6)
	else
		Line(tt, "Price left after buying", d.competitor and Money(d.competitor) or "none listed")
	end
	if d.stats and d.stats.avgSale then
		Line(tt, "Your sales (14 days)", Money(d.stats.avgSale) .. " each")
	end
	Line(tt, "Prudent resale price", Money(d.resell))
	if d.observedF then
		Line(tt, "Deposits lost per unit sold", Money(d.F))
	else
		Line(tt, format("Deposits of %d failed posts", DB().settings.failures), Money(d.F) .. (d.depositKnown and "" or " (estimate)"))
	end
	Line(tt, format("Max buy = (P x %.2f - F) / %.2f", 1 - Eco.cut, 1 + d.r), Money(d.maxBuy))
	tt:AddLine(" ")
	Line(tt, format("%d units under the max", d.units), Money(d.dealCost) .. " -> " .. ProfitText(d.potential))
	Line(tt, "If the price drops 10 %", ProfitText(d.stress))
	Line(tt, format("Cap: %d%% of the budget %s", floor(d.capPct * 100 + 0.5), Money(d.budget)), Money(d.cap))
	if d.stats and d.stats.stock > 0 then
		Line(tt, "Your stock", d.stats.stock .. " (" .. Money(d.stats.stockCost) .. ")")
	end
	if d.unitLimit < math.huge then
		Line(tt, "Two days of your sales", "+" .. d.unitLimit .. " units at most")
	end
	Line(tt, "Buy now", d.buy .. " units, " .. Money(d.cost) .. " -> " .. ProfitText(d.profit))
	if d.buy == 0 then
		local why = (d.capPct == 0 and "Risky: no purchase.")
			or (d.unitLimit == 0 and "You already hold two days of your sales.")
			or (d.room <= 0 and "Budget used: the cap of this item, or half of your budget, is already in stock.")
			or "One unit costs more than what the cap leaves."
		tt:AddLine(why, 1, 0.5, 0.3, true)
	end
	if d.days < 7 then
		tt:AddLine("Under 7 days of history: observe, test purchases only.", 0.8, 0.8, 0.8, true)
	end
	if not (d.stats and d.stats.sellThrough) then
		tt:AddLine("No confirmed sale yet: this only justifies a test purchase.", 0.8, 0.8, 0.8, true)
	end
	tt:AddLine("Click: search it at the auction house  -  Right click: watch it in Market", 0.5, 0.8, 1, true)
	tt:Show()
end

local function MarketTooltip(row, d)
	local tt = ItemTooltip(row, d)
	local i, rec, s = d.ind, d.rec, d.stats
	tt:AddLine(" ")
	Line(tt, "Price now (20 % of the quantity)", Money(d.price))
	Line(tt, "M3 / M14", Money(i.m3) .. " / " .. Money(i.m14))
	Line(tt, "Price trend (3 days / 14)", (SignedText(i.trend)))
	Line(tt, "Spread", Pct(i.spread))
	tt:AddLine(" ")
	Line(tt, "Listed now", Thousands(d.listed) .. (d.near and ("  (" .. Thousands(d.near) .. " near the price)") or ""))
	local slot = floor((tonumber(date("%H")) or 0) / 4)
	if rec.qs and rec.qs[slot] then
		Line(tt, "Usual at this time of day", Thousands(rec.qs[slot]) .. "  (" .. (SignedText(d.now)) .. ")")
	end
	if i.vol14 then
		Line(tt, "Listed per day, 3 / 14 days", Thousands(i.vol3 or 0) .. " / " .. Thousands(i.vol14) .. "  (" .. (SignedText(i.supply)) .. ")")
	end
	if i.near14 then
		Line(tt, "Near the price, 3 / 14 days", Thousands(i.near3 or 0) .. " / " .. Thousands(i.near14) .. "  (" .. (SignedText(i.nearSupply)) .. ")")
	end
	Line(tt, "History", i.days .. " days of prices, " .. (i.volDays or 0) .. " of supply")
	if s and (s.sold > 0 or s.bought > 0) then
		tt:AddLine(" ")
		Line(tt, "Your sales per day (7 days)", format("%.1f", s.velocity))
		if s.sellThrough then
			Line(tt, "Sold within 48 h", Pct(s.sellThrough))
		end
		Line(tt, "Your realized profit", ProfitText(s.profit))
	end
	local c = CONFIDENCE[d.confidence]
	Line(tt, "Confidence", c[1], c[2], c[3], c[4])
	tt:AddLine("A falling supply alone is never a reason to buy.", 0.7, 0.7, 0.7, true)
	tt:AddLine("Click: history  -  Shift click: search it  -  Right click: " .. (d.watched and "stop watching" or "watch"), 0.5, 0.8, 1, true)
	tt:Show()
end

local ADVICE = {
	["Sell it off"] = "Unsold for 7 days: lower the price step by step, a small loss beats a stuck stock.",
	["Stop buying"] = "Under 30 % sold within 48 h: no new purchase.",
	["Check the price"] = "3 days in stock: compute the prudent price and the fees again.",
	["Check competition"] = "A day in stock: check the prices, the competition and the stack sizes.",
}

local function TradeTooltip(row, d)
	local tt = ItemTooltip(row, d)
	tt:AddLine(" ")
	Line(tt, "Bought", d.bought .. " for " .. Money(d.boughtCost))
	Line(tt, "Sold", d.sold .. " for " .. Money(d.gross) .. " (before the cut)")
	if d.vendorSold > 0 then
		Line(tt, "Sold to vendors", d.vendorSold .. " for " .. Money(d.vendorGross))
	end
	if d.onAH > 0 then
		Line(tt, "On the auction house", d.onAH .. " (deposits paid " .. Money(d.tied) .. ")")
	end
	Line(tt, "Sales per day (7 days)", format("%.1f", d.velocity))
	if d.sellThrough then
		Line(tt, "Sold within 48 h", Pct(d.sellThrough) .. " (" .. d.evalLots .. " lots)")
	end
	Line(tt, "Posts", tostring(d.posts))
	Line(tt, "Deposits lost", Money(d.lost))
	Line(tt, "Realized profit", ProfitText(d.profit))
	if d.stock > 0 then
		Line(tt, "Stock", d.stock .. ", cost " .. Money(d.stockCost))
		Line(tt, "Oldest unit bought", Age(d.age) .. " ago")
		local unit = (d.stockCost + (d.lostOnStock or 0)) / d.stock
		Line(tt, "No-loss price", Money(unit / (1 - Eco.cut)) .. " each")
		tt:AddLine("It tells where you stand, not that a buyer will pay it.", 0.7, 0.7, 0.7, true)
	end
	if ADVICE[d.advice] then
		tt:AddLine(ADVICE[d.advice], d.adviceColor[1], d.adviceColor[2], d.adviceColor[3], true)
	end
	tt:AddLine("Click: search it at the auction house", 0.5, 0.8, 1)
	tt:AddLine("Shift + right click: forget this stock (used or sold elsewhere)", 0.6, 0.6, 0.6)
	tt:Show()
end

local function CraftTooltip(row, d)
	local tt = ItemTooltip(row, d)
	tt:AddLine(" ")
	tt:AddDoubleLine("Profession", d.prof, 1, 0.82, 0, 1, 1, 1)
	if d.mv then
		tt:AddDoubleLine("Market value (" .. d.days .. " days)", Money(d.mv), 1, 0.82, 0, 1, 1, 1)
	end
	tt:AddLine("Click: details, right click: search it at the auction house", 0.5, 0.8, 1)
	tt:Show()
end

local function Percent(x)
	local v = floor(x * 1000 + 0.5) / 10
	if v == floor(v) then
		return format("%d%%", v)
	end
	return format("%.1f%%", v)
end

-- the item of an offer of a lot ({ price, key, link })
local function OfferItem(o)
	return (o[3] and Item(o[3])) or Item(BaseID(o[2]))
end

-- the state of an item of a lot, in words
local ITEM_STATE = {
	ok = "|cff40ff40confirmed|r", no = "|cffff4040cannot be disenchanted|r", unknown = "|cffffd100not known|r",
	who = "|cffff8040no enchanter|r", whole = "|cff80c0ffworth more whole|r",
}

-- the items of the n cheapest auctions of a lot (the model: Opportunities.lua)
local Picked = Eco.LotPicked

local function EntryItem(entry)
	return OfferItem({ nil, entry.key, entry.link })
end

-- how old the prices and the auctions are, and what a quick scan misses
local function ScanAge()
	local _, r = DB()
	local text = format("Prices and auctions of the last scan: %s (%s)", Eco.Ago(r.lastScan), r.lastMode or "?")
	if r.lastMode == "quick" then
		text = text .. format("; a quick scan sees only the cheapest auction of each item, the others come from the full scan of %s and may be gone", Eco.Ago(r.fullAt))
	end
	return text .. ". What is seen may have been bought since."
end

-- a lot: can it be disenchanted, what one disenchant gives (estimate), what
-- that sells for (estimate), the exact items to buy and those left out, the
-- model's chance
local function EnchantTooltip(row, d)
	local tt = GameTooltip
	tt:SetOwner(row, "ANCHOR_RIGHT")
	tt:AddLine(d.label, QualityColor(d.quality))
	local s = Eco.DE_STATUS[d.status] or Eco.DE_STATUS.none
	tt:AddLine(s[1] .. ": " .. s[6], s[2], s[3], s[4], true)
	-- 1. can its items be disenchanted, by whom
	tt:AddLine(" ")
	tt:AddLine("1. Can it be disenchanted", 1, 0.82, 0)
	Line(tt, "Items confirmed by the game", format("%d (%d units seen)", #d.items, d.available))
	if #d.excluded > 0 then
		Line(tt, "Items left out", tostring(#d.excluded), 1, 0.5, 0.3)
	end
	Line(tt, format("Enchanting %d (classic table)", d.skill or 1), d.can and d.how or ("|cffff6060" .. tostring(d.how) .. "|r"))
	-- 2. what one disenchant gives
	tt:AddLine(" ")
	if d.validated then
		tt:AddLine("2. One disenchant gives (yield table validated on this client):", 1, 0.82, 0)
	else
		tt:AddLine("2. One disenchant gives, ESTIMATE (classic yield table, not validated on this client):", 1, 0.6, 0.2, true)
	end
	for _, r in ipairs(d.results) do
		local mi = Item(r[1])
		local qty = r[3] == r[4] and tostring(r[3]) or (r[3] .. "-" .. r[4])
		tt:AddLine(format("%s   %s x %s", Percent(r[2]), qty, mi and mi.name or ("item " .. r[1])), 1, 1, 1)
	end
	local seen = Eco.DESeen().lots[d.key]
	if seen and seen.n > 0 then
		tt:AddLine(format("Disenchants of this lot seen on this client: %d.", seen.n), 0.7, 0.7, 0.7)
	end
	-- 3. what the materials sell for
	tt:AddLine(" ")
	tt:AddLine(format("3. Their sale, ESTIMATE (auction house prices, %d %% cut taken off):", floor(Eco.cut * 100 + 0.5)), 1, 0.82, 0, true)
	local _, mr = DB()
	for _, r in ipairs(d.results) do
		local mi = Item(r[1])
		local v = MaterialValue(r[1])
		local rec = mr.items[r[1]]
		local listed = rec and rec.s == mr.scanId and rec.q
		tt:AddDoubleLine(mi and mi.name or ("item " .. r[1]), (v and (Money(v) .. " each") or "|cffff8040no price|r")
			.. (listed and ("  (" .. Thousands(listed) .. " listed)") or "  (none listed)"), 1, 1, 1, 1, 1, 1)
	end
	Line(tt, "Mean of a disenchant (break-even price)", Money(d.mean))
	Line(tt, "Give or take (standard deviation)", Money(d.sd))
	if d.missing then
		tt:AddLine("A material has no price yet: counted as 0.", 1, 0.5, 0.3, true)
	end
	-- 4. the auctions: the exact items
	tt:AddLine(" ")
	Line(tt, format("Max price (return %d %% or more)", d.minReturn), "|cffffd100" .. Money(d.most) .. "|r each")
	local n = d.buy or d.available
	if n > 0 then
		local verb = d.ok and "To buy" or "Items of the computation (not advised)"
		tt:AddLine(format("%s, %d of the cheapest:", verb, n), 1, 0.82, 0)
		local picked = Picked(d, n)
		for i = 1, math.min(#picked, 10) do
			local p = picked[i]
			local it = OfferItem({ nil, p.key, p.link })
			local r, g, b = QualityColor(it and it.quality)
			tt:AddDoubleLine(format("%s x%d", it and it.name or ("item " .. tostring(p.key)), p.count),
				format("up to %s each, %s", Money(p.top), ITEM_STATE.ok), r, g, b, 1, 1, 1)
		end
		if #picked > 10 then
			tt:AddLine(format("... and %d more items (shift-click: all of them in the chat)", #picked - 10), 0.7, 0.7, 0.7)
		end
		Line(tt, "Cost", Money(d.cost) .. "  (" .. Money(d.avg) .. " each on average)")
		Line(tt, "Expected profit (model)", ProfitText(d.profit) .. "  (" .. Pct(d.ret) .. ")")
		if d.chance then
			Line(tt, "Model chance of a profit", format("%d%%", floor(d.chance * 100)))
			tt:AddLine("The model's: its yield table, the prices of the last scan, every auction still there. Not a guarantee.", 0.7, 0.7, 0.7, true)
		end
		if d.low then
			Line(tt, "1 time in 10 (model), less than", ProfitText(d.low))
			Line(tt, "1 time in 10 (model), more than", ProfitText(d.high))
		end
		if d.planned then
			tt:AddLine("In your capital's plan (the whole plan: under the list).", 0.3, 1, 0.3, true)
		elseif d.plan and d.need and d.validated then
			tt:AddLine("Out of your capital's plan: it went to better returns.", 1, 0.5, 0.2, true)
		end
	else
		tt:AddLine(format("No auction of a confirmed item with a return of %d %% or more in the last scan.", d.minReturn), 0.7, 0.7, 0.7, true)
	end
	-- the items left out: never counted
	if #d.excluded > 0 then
		tt:AddLine(" ")
		tt:AddLine("Left out (not in the quantities, the cost or the profit):", 1, 0.5, 0.3)
		for i = 1, math.min(#d.excluded, 8) do
			local entry = d.excluded[i]
			local it = EntryItem(entry)
			local r, g, b = QualityColor(it and it.quality)
			tt:AddDoubleLine(format("%s%s", it and it.name or ("item " .. tostring(entry.key)), entry.units > 0 and format(" x%d", entry.units) or ""),
				ITEM_STATE[entry.state] or entry.state, r, g, b, 1, 1, 1)
			tt:AddLine("   " .. tostring(entry.why), 0.7, 0.7, 0.7, true)
		end
		if #d.excluded > 8 then
			tt:AddLine(format("... and %d more (shift-click: all of them in the chat)", #d.excluded - 8), 0.7, 0.7, 0.7)
		end
	end
	tt:AddLine(" ")
	tt:AddLine(ScanAge(), 0.7, 0.7, 0.7, true)
	if n > 0 then
		tt:AddLine("Click: search the next item of the list at the auction house; shift-click: the exact items in the chat", 0.5, 0.8, 1, true)
	else
		tt:AddLine("Shift-click: the exact items in the chat", 0.5, 0.8, 1)
	end
	tt:Show()
end

-- shift-click on a lot: its exact items in the chat (links, quantity, max
-- unit price, state), then those left out and why
function Eco.PrintLot(d)
	local s = Eco.DE_STATUS[d.status] or Eco.DE_STATUS.none
	ns.Print(format("%s: %s%s (yield table %s)", d.label, s[1], d.ok and "" or " - not advised",
		d.validated and "validated on this client" or "not validated on this client: estimate"))
	local n = d.buy or d.available
	local byKey = {}
	for _, entry in ipairs(d.items) do
		byKey[entry.key] = entry
	end
	for _, p in ipairs(Picked(d, n)) do
		local it = OfferItem({ nil, p.key, p.link })
		local entry = byKey[p.key]
		ns.Print(format("  %s x%d, up to %s each - confirmed: %s; %s", (it and it.link) or p.link or ("item " .. tostring(p.key)), p.count,
			Money(p.top), entry and tostring(entry.why) or "?", entry and tostring(entry.how) or "?"))
	end
	for _, entry in ipairs(d.excluded) do
		local it = EntryItem(entry)
		ns.Print(format("  |cffff8040left out|r %s%s: %s - %s", (it and it.link) or entry.link or ("item " .. tostring(entry.key)),
			entry.units > 0 and format(" (x%d up to %s)", entry.units, Money(entry.top)) or "", ITEM_STATE[entry.state] or entry.state, tostring(entry.why)))
	end
	ns.Print("  " .. ScanAge())
end

local function ScanTooltip(self)
	local tt = GameTooltip
	tt:SetOwner(self, "ANCHOR_TOP")
	tt:AddLine("Auction house scan", 1, 0.82, 0)
	local full, wait = Eco.CanFullScan()
	if full then
		tt:AddLine("Full scan: every auction of the auction house. Once per 15 min for the account.", 1, 1, 1, true)
	else
		tt:AddLine(format("Quick scan: the lowest price of every item. Full scan again in %d min.", ceil(wait / 60)), 1, 1, 1, true)
	end
	tt:Show()
end

-- the line under the lots: the plan of the capital (target: the chance
-- asked for; info: what Eco.ComputeEnchant left out; good: lots advised)
local function PlanText(plan, target, info, good)
	-- (no lot advised because no yield table is validated here: said first)
	if info and (info.modelLots or 0)>0 and not plan then
        return format("%d estimated lots meet your filters. Set a budget in Settings for a combined plan.",info.modelLots)
    elseif (good or 0) == 0 and info and info.estimates > 0 and not (plan and plan.items > 0) then
		return format("|cffff8033No purchase advised:|r |cffa0a0a0the yield tables are classic ones, not validated on this client (%d lots: estimates only, \"Every lot\" shows them).|r", info.estimates)
	elseif not plan and info and info.excluded>0 and (info.modelLots or 0)==0 then
        return "No eligible lot meets the filters. Show excluded / rejected lots to inspect the reasons."
	elseif not plan then
		return "|cffa0a0a0No capital: the smallest safe lot of each kind. Enter a capital: a plan spends it on the best returns of every lot.|r"
	elseif plan.items == 0 and plan.smallest then
		return format("|cffffd100Plan for %s:|r too small for a safe lot: the smallest costs %s.", Money(plan.capital), Money(plan.smallest))
	elseif plan.items == 0 then
		return format("|cffffd100Plan for %s:|r nothing to buy: no lot of confirmed items your enchanters can disenchant reaches the chance asked for (a full scan sees more auctions, a lower return lets more in).", Money(plan.capital))
	end
	local chance = format("%d%%", floor(plan.chance * 100))
	local text = format("|cffffd100Model plan for %s:|r %d items in %d lots, cost %s, profit %s (%s), model chance %s",
		Money(plan.capital), plan.items, plan.lots, Money(plan.cost), ProfitText(plan.profit), Pct(plan.profit / plan.cost),
		plan.chance >= target and ("|cff4dff4d" .. chance .. "|r") or ("|cffff8033" .. chance .. "|r"))
	if plan.estimated then text=text.." |cffffcc66Classic yields; unverified on this server.|r" end
	if plan.chance < target then
		text = text .. " |cffff8033- under the chance asked for: more capital or a higher return makes it safer|r"
	elseif plan.left >= plan.capital * 0.1 then
		text = text .. format(" |cffa0a0a0- %s left: no other auction with the return|r", Money(plan.left))
	end
	return text
end

-- the plan in a tooltip
local function PlanTooltip(owner, plan)
	if not (plan and plan.items > 0) then
		return
	end
	local tt = GameTooltip
	tt:SetOwner(owner, "ANCHOR_TOP")
	tt:AddLine(format("Plan for %s", Money(plan.capital)), 1, 0.82, 0)
	tt:AddLine("Every lot safe on its own (the chance asked for), the best returns first, every lot together, until your capital is spent: the most expected profit for it. The whole plan is safer still: several lots together.", 1, 1, 1, true)
	tt:AddLine(" ")
	Line(tt, "Items, lots", plan.items .. ", " .. plan.lots)
	Line(tt, "Cost", Money(plan.cost))
	Line(tt, "Materials (expected)", Money(plan.value))
	Line(tt, "Expected profit (model)", ProfitText(plan.profit) .. "  (" .. Pct(plan.profit / plan.cost) .. ")")
	Line(tt, "Model chance of a profit", format("%d%%", floor(plan.chance * 100)))
	Line(tt, "1 time in 10 (model), less than", ProfitText(plan.low))
	Line(tt, "1 time in 10 (model), more than", ProfitText(plan.high))
	if plan.left > 0 then
		Line(tt, "Capital left", Money(plan.left))
	end
	tt:AddLine(" ")
	tt:AddLine("The model's chance: its yield tables, the prices of the last scan, every auction still there. Not a guarantee.", 0.7, 0.7, 0.7, true)
	tt:AddLine(ScanAge(), 0.7, 0.7, 0.7, true)
	tt:Show()
end

-- a craft of Synergy: who makes it, the shopping list, what its
-- disenchants make
local function SortedKeys(t)
	local keys = {}
	for k in pairs(t) do
		keys[#keys + 1] = k
	end
	table.sort(keys)
	return keys
end

local function SynergyTooltip(row, d)
	local tt = ItemTooltip(row, d)
	local cr, o = d.crafter, d.o
	tt:AddLine(" ")
	Line(tt, "Crafted by", format("%s (%s %s)", cr.who, cr.prof, tostring(cr.live or cr.p.r or "?")))
	local crafts = d.crafts or 1
	local list = Eco.ShoppingList(d.rc, crafts, d.own)
	tt:AddLine(" ")
	tt:AddLine(format("1. Buy, for %d craft%s:", crafts, crafts > 1 and "s" or ""), 1, 0.82, 0)
	for _, id in ipairs(SortedKeys(list.buy)) do
		local b = list.buy[id]
		local it = Item(id)
		local where = b.src == "vendor" and "|cff40ff40vendor|r" or format("AH, up to %s each", Money(b.top))
		tt:AddDoubleLine(format("%s x %s", Thousands(b.qty), it and it.name or ("item " .. id)), Money(b.cost) .. "  " .. where, 1, 1, 1, 1, 1, 1)
	end
	if list.missing then
		tt:AddLine("Not all of them to be had: fewer listed than needed.", 1, 0.4, 0.4, true)
	end
	local step = 2
	local first = SortedKeys(list.craft)
	if #first > 0 then
		tt:AddLine("2. Craft first:", 1, 0.82, 0)
		for _, id in ipairs(first) do
			local it, sub = Item(id), d.own[id]
			tt:AddLine(format("%s x %s", Thousands(list.craft[id] * (sub and sub.n or 1)), it and it.name or ("item " .. id)), 1, 1, 1)
		end
		step = 3
	end
	local product = o and o.item and o.item.name or ("item " .. d.id)
	local units = crafts * d.made
	if d.level then
		tt:AddLine(format("%d. Craft %s, then %s.", step, product, o and o.outlet == "de" and "disenchant it" or "sell it to a vendor"), 1, 0.82, 0)
	else
		tt:AddLine(format("%d. Craft %s x %s, disenchant them, sell the materials:", step, Thousands(units), product), 1, 0.82, 0)
		for _, r in ipairs(o.lot.def.results) do
			local mi = Item(r[1])
			local v = MaterialValue(r[1])
			tt:AddDoubleLine(format("about %.1f x %s", units * r[2] * (r[3] + r[4]) / 2, mi and mi.name or ("item " .. r[1])),
				v and (Money(v) .. " each") or "|cffff8040no price|r", 1, 1, 1, 0.7, 0.7, 0.7)
		end
	end
	tt:AddLine(" ")
	-- can the product be disenchanted (as in Enchant), by whom
	if o and o.lot then
		local state = Eco.DE_STATE_TEXT[o.state] or tostring(o.state)
		tt:AddLine(format("Disenchant: %s - %s", state, tostring(o.state == "ok" and not o.deOk and o.how or o.why)), 1, 1, 1, true)
		if o.deOk then
			Line(tt, "Disenchanted by", o.how)
		elseif o.deEst then
			Line(tt, "Disenchanted by", o.estHow)
			tt:AddLine("The game has not confirmed it can be disenchanted: an estimate. Craft one and try Disenchant on it before making more.", 1, 0.6, 0.2, true)
		elseif o.state == "ok" then
			tt:AddLine("No enchanter of your account can disenchant it: not counted as disenchanted.", 1, 0.4, 0.4, true)
		else
			tt:AddLine("Not confirmed by the game: not counted as disenchanted.", 1, 0.4, 0.4, true)
		end
		if o.estimate and (o.de or o.deEst) then
			tt:AddLine("Its yield table is a classic one, not validated on this client: the figures are estimates, not an advice.", 1, 0.6, 0.2, true)
		end
	end
	if d.level then
		Line(tt, "Chance of a skill point", d.points and format("%d%%", floor(d.points * 100 + 0.5)) or "? (open the profession window)")
		if d.perPoint then
			Line(tt, "A skill point costs", ProfitText(-d.perPoint))
		end
	elseif d.chance then
		Line(tt, "Expected profit (model)", ProfitText(d.profit) .. "  (" .. Pct(d.ret) .. ")")
		Line(tt, "Model chance of a profit", format("%d%%", floor(d.chance * 100)))
		tt:AddLine("The model's: its yield table, the prices of the last scan. Not a guarantee.", 0.7, 0.7, 0.7, true)
		if d.estimate then
			tt:AddLine("Estimate only: no craft advised until the yield table is validated on this client.", 1, 0.6, 0.2, true)
		elseif not d.ok then
			tt:AddLine(d.capital > 0 and "Your capital is too small for the chance asked for (or the materials run out)." or "Not safe enough: the materials run out before the chance asked for.", 1, 0.5, 0.2, true)
		end
	elseif d.one and (o.de or o.deEst) and not d.ok then
		tt:AddLine(d.one > d.value and "Not profitable: one craft costs more than its disenchant brings." or "Your capital does not pay one craft.", 1, 0.5, 0.2, true)
	end
	if o and o.ah then
		tt:AddDoubleLine("(sold whole instead, after the cut)", Money(o.ah), 0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
		if d.whole and not d.level then
			tt:AddLine("Sold whole it would bring more than its disenchant, if it sells: few buyers for crafted gear.", 1, 0.6, 0.2, true)
		end
	end
	tt:AddLine("Click: search the next thing to buy at the auction house; right click: the product", 0.5, 0.8, 1, true)
	tt:Show()
end

Eco.View = {
	COLUMNS = COLUMNS, CONFIDENCE = CONFIDENCE, ItemOf = ItemOf, NameText = NameText, Pct = Pct, SignedText = SignedText,
	ItemTooltip = ItemTooltip, Line = Line, OfferItem = OfferItem, ScanTooltip = ScanTooltip, DealTooltip = DealTooltip,
	MarketTooltip = MarketTooltip, TradeTooltip = TradeTooltip, CraftTooltip = CraftTooltip, EnchantTooltip = EnchantTooltip,
	PlanText = PlanText, PlanTooltip = PlanTooltip, SynergyTooltip = SynergyTooltip,
}
