--[[
	WC3 Console - economy: Make Gold and Market as The Goblin Ledger shows
	them. Figures only: each method's opportunities come from the existing
	computations (Eco.ComputeDeals, ComputeCrafts, ComputeEnchant,
	ComputeSynergy), never computed again here; this file only says, for each
	of them and in the same words everywhere:
	  eligibility   can it be done (who, what is needed, what is left out)
	  data quality  how far the prices behind it can be trusted
	  estimate      what it should bring: an estimate, never a promise
	  verified      eligible, data good enough, and the computation advises it
	A sheet tells what to buy (exact items, quantities, max unit prices),
	what to do, the expected outcome, the fees and the assumptions. Nothing
	here buys, sells or disenchants: the ledger only prepares and explains.
]]

local _, ns = ...
local Eco = ns.Economy
local floor, max, min, format = math.floor, math.max, math.min, string.format
local pairs, ipairs, type, tostring = pairs, ipairs, type, tostring
local sort = table.sort

local DB, Item, BaseID, Indicators, Money = Eco.DB, Eco.Item, Eco.BaseID, Eco.Indicators, Eco.Money
local HOUR, DAY = Eco.HOUR, Eco.DAY

------------------------------------------------------------------------
-- Data quality of the prices of an item: 0 not enough data, 1 poor, 2
-- fair, 3 good; the reasons (words)
------------------------------------------------------------------------

local QUALITY = { [0] = "Not enough data", "Poor", "Fair", "Good" }
Eco.QUALITY = QUALITY

function Eco.DataQuality(key)
	local _, r = DB()
	local rec = r.items[key]
	local reasons = {}
	if not (rec and (rec.h or rec.hp)) then
		return 0, { "no price history yet" }
	end
	local ind = Indicators(rec)
	local level = 3
	local function Cap(l, why)
		level = min(level, l)
		reasons[#reasons + 1] = why
	end
	if ind.days < 3 then
		Cap(0, format("%d day%s of prices (3 needed)", ind.days, ind.days == 1 and "" or "s"))
	elseif ind.days < 7 then
		Cap(1, format("%d days of prices (7 for a fair view)", ind.days))
	elseif ind.days < 14 then
		Cap(2, format("%d days of prices (14 for a good view)", ind.days))
	end
	if ind.spread and ind.spread > 0.30 then
		Cap(1, format("prices spread widely (%d %%)", floor(ind.spread * 100 + 0.5)))
	elseif ind.spread and ind.spread > 0.15 then
		Cap(2, format("prices spread (%d %%)", floor(ind.spread * 100 + 0.5)))
	end
	local age = r.lastScan and time() - r.lastScan
	if not age or age > 12 * HOUR then
		Cap(1, "last scan " .. Eco.Ago(r.lastScan))
	elseif age > 3 * HOUR then
		Cap(2, "last scan " .. Eco.Ago(r.lastScan))
	end
	if rec.s ~= r.scanId then
		Cap(1, "not listed in the last scan")
	elseif r.lastMode == "quick" then
		Cap(2, "quick scan: its lowest auction only")
	end
	if #reasons == 0 then
		reasons[1] = format("%d days of prices, tight, scanned %s", ind.days, Eco.Ago(r.lastScan))
	end
	return level, reasons
end

-- the worst quality of several keys
local function Worst(keys)
	local level, reasons = 3, {}
	for _, key in ipairs(keys) do
		local l, why = Eco.DataQuality(key)
		if l < level then
			level = l
		end
		if l < 3 then
			local it = Item(BaseID(key))
			reasons[#reasons + 1] = (it and it.name or ("item " .. tostring(key))) .. ": " .. why[1]
		end
	end
	return level, reasons
end

------------------------------------------------------------------------
-- The methods
------------------------------------------------------------------------

local METHODS = {
	{ key = "resell", label = "Buy & Resell", icon = [[Interface\Icons\INV_Misc_Coin_01]],
		explain = "Buy under the usual price, sell again at the auction house, or to a vendor when it pays more than its price.",
		prereq = "A scan of the auction house; 7 days of prices or more for a resale." },
	{ key = "craft", label = "Craft & Sell", icon = [[Interface\Icons\Trade_BlackSmithing]],
		explain = "Craft with your recipes when the materials cost less than the product sells for.",
		prereq = "Your recipes (open your profession windows once); prices of the materials and of the product." },
	{ key = "de", label = "Disenchant", icon = [[Interface\Icons\INV_Enchant_Disenchant]],
		explain = "Buy gear the game confirms can be disenchanted, disenchant it, sell the materials.",
		prereq = "An enchanter of yours on this realm and side, its rank known; each item confirmed by the game. Profit uses a classic probability model, unverified on this server." },
	{ key = "craftde", label = "Craft & Disenchant", icon = [[Interface\Icons\Trade_Engraving]],
		explain = "Craft gear to disenchant it and sell the materials, or to level a profession at the lowest cost.",
		prereq = "Recipes of a crafter of yours, an enchanter of yours, items confirmed by the game; yields are model estimates." },
}
Eco.METHODS = METHODS
for _, m in ipairs(METHODS) do
	METHODS[m.key] = m
end

local cache = {} -- method -> rows (this pass)
function Eco.OppReset()
	cache = {}
end

-- the rows of the n cheapest auctions of a lot, by item: { key, link,
-- count, top: the dearest unit price paid }, cheapest first
function Eco.LotPicked(d, n)
	local byKey, list = {}, {}
	for i = 1, min(n or 0, #d.offers) do
		local o = d.offers[i]
		local p = byKey[o[2]]
		if not p then
			p = { key = o[2], link = o[3], count = 0, top = 0 }
			byKey[o[2]] = p
			list[#list + 1] = p
		end
		p.count, p.top = p.count + 1, max(p.top, o[1])
	end
	return list
end

-- One opportunity: method, key, id (its icon, its name) or label, cost,
-- net (estimated net profit), quality (level, reasons), eligible, why
-- (not eligible: why), verified, d (the computation's row)
local function Row(method, d, t)
	t.method, t.d = method, d
	t.stamp = t.verified and "verified" or "review"
	return t
end

local Build = {}

function Build.resell()
	local rows = Eco.ComputeDeals()
	local shown = Eco.FilterDeals(rows)
	local out = {}
	for _, d in ipairs(shown) do
		local level, reasons
		if d.status == "vendor" then
			-- (the vendor price is sure: the scan's age only)
			level, reasons = 3, { "vendor price: known" }
			local _, r = DB()
			if r.lastScan and time() - r.lastScan > 3 * HOUR then
				level, reasons = 2, { "vendor price known; auctions scanned " .. Eco.Ago(r.lastScan) }
			end
		else
			level, reasons = Eco.DataQuality(d.key)
		end
		local advised = d.status == "vendor" or d.status == "proven" or d.status == "good"
		local buyNow = (d.buy or 0) > 0
		out[#out + 1] = Row("resell", d, {
			key = "resell:" .. tostring(d.key), id = d.id, link = d.link,
			cost = buyNow and d.cost or d.dealCost or d.cost, net = buyNow and d.profit or d.potential,
			quality = level, reasons = reasons, eligible = true,
			verified = advised and buyNow and level >= 2,
			note = Eco.STATUS[d.status] and Eco.STATUS[d.status][1],
		})
	end
	return out
end

function Build.craft()
	local out = {}
	for _, d in ipairs(Eco.ComputeCrafts()) do
		local keys = { d.id }
		for id in pairs(d.rc.r) do
			keys[#keys + 1] = id
		end
		local level, reasons = Worst(keys)
		local known = d.cost ~= nil and d.profit ~= nil
		out[#out + 1] = Row("craft", d, {
			key = "craft:" .. d.key, id = d.id, cost = d.cost, net = d.profit, quality = level, reasons = reasons,
			eligible = known, why = not known and "a material or the product has no price" or nil,
			verified = known and d.profit > 0 and level >= 2 and (d.listed or 0) > 0,
		})
	end
	return out
end

function Build.de()
	local out = {}
	local list = Eco.ComputeEnchant()
	for _, d in ipairs(list) do
		local mats = {}
		for _, res in ipairs(d.results) do
			mats[#mats + 1] = res[1]
		end
		local level, reasons = Worst(mats)
		if not d.validated then
			level = min(level, 1)
			table.insert(reasons, 1, "yield table not validated on this client: an estimate")
		end
		local why
		if d.available == 0 then
			why = #d.excluded > 0 and "no item both confirmed by the game and disenchantable by an enchanter of yours" or "no auction at the max price"
		end
		out[#out + 1] = Row("de", d, {
			key = "de:" .. d.key, label = d.label, icon = d.icon, itemQuality = d.quality, cost = d.cost, net = d.profit,
			quality = level, reasons = reasons, eligible = d.available > 0, why = why, verified = d.ok == true,
			note = Eco.DE_STATUS and Eco.DE_STATUS[d.status] and Eco.DE_STATUS[d.status][1],
		})
	end
	return out
end

function Build.craftde()
	local out = {}
	local rows = Eco.ComputeSynergy()
	for _, d in ipairs(rows) do
		local keys = { d.id }
		for id in pairs(d.rc.r) do
			keys[#keys + 1] = id
		end
		if d.o and d.o.lot then
			for _, res in ipairs(d.o.lot.def.results) do
				keys[#keys + 1] = res[1]
			end
		end
		local level, reasons = Worst(keys)
		if d.o and d.o.estimate then
			level = min(level, 1)
			table.insert(reasons, 1, "yield table not validated on this client: an estimate")
		end
		if d.unconfirmed then
			level = min(level, 1)
			table.insert(reasons, 1, "the game has not confirmed the product can be disenchanted: try one first")
		end
		local o = d.o
		local why
		if not (o and o.lot) then
			why = "its product cannot be disenchanted"
		elseif o.state ~= "ok" then
			why = "not confirmed by the game: " .. tostring(o.why)
		elseif not o.deOk then
			why = tostring(o.how or o.why)
		elseif not d.one then
			why = "not all of its materials can be had"
		end
		out[#out + 1] = Row("craftde", d, {
			key = "craftde:" .. d.key, id = d.id, cost = d.level and d.one or d.cost, net = d.level and (d.net and -d.net) or d.profit,
			quality = level, reasons = reasons, eligible = why == nil, why = why, verified = d.ok == true and not d.level,
			state = o and o.lot and o.state or nil,
		})
	end
	return out
end

-- the opportunities of a method (cached for this pass)
function Eco.Opportunities(method)
	local rows = cache[method]
	if not rows then
		rows = Build[method] and Build[method]() or {}
		cache[method] = rows
	end
	return rows
end

-- How a method stands: state ("ok", "unavailable", "missing", "none"), the
-- verified opportunities, all of them, a line saying it, the needs (each:
-- text, met)
function Eco.MethodSummary(key)
	local e, r = DB()
	local needs, state, line = {}, "ok", nil
	local function Need(text, met)
		needs[#needs + 1] = { text = text, met = met }
	end
	local rows = Eco.Opportunities(key)
	local scanned = r.lastScan ~= nil
	Need(scanned and ("auction house scanned " .. Eco.Ago(r.lastScan)) or "no scan of the auction house yet", scanned)
	if key == "craft" or key == "craftde" then
		local any = false
		if key == "craft" then
			any = next(Eco.Recipes()) ~= nil
		else
			any = #Eco.Crafters() > 0
		end
		Need(any and "recipes known" or "no recipe yet: open your profession windows", any)
		if not any then
			state = "unavailable"
		end
	end
	if key == "de" or key == "craftde" then
		local list = Eco.DEEnchanters()
		local best
		for _, en in ipairs(list) do
			if en.rank and en.spell ~= false then
				best = max(best or 0, en.rank)
			end
		end
		Need(best and format("enchanter: Enchanting %d", best) or (#list > 0 and "enchanter's rank not known: log on it once" or "no enchanter on this realm and side"), best ~= nil)
		if not best then
			state = "unavailable"
		end
		local stats = Eco.deReport or Eco.DEStats()
		Need(format("items confirmed: %d; unknown: %d; forbidden: %d", stats.ok, stats.unknown, stats.no), stats.ok > 0)
		local anyValidated = false
		for _, v in pairs(Eco.DE.VALIDATED[Eco.CLIENT_VERSION] or {}) do
			anyValidated = anyValidated or v
		end
		Need(anyValidated and "Server-validated yield tables available" or "Model available: Classic probabilities (server yields unverified)", true)
		if state == "ok" and stats.ok == 0 then
			state = "missing"
		end
	end
	if not scanned and state == "ok" then
		state = "missing"
	end
	if state == "unavailable" then rows = {} end
	local verified, estimated = 0, 0
	for _, row in ipairs(rows) do
        if row.d and row.d.modelReady and not row.verified then estimated=estimated+1 end
		if row.verified then
			verified = verified + 1
		end
	end
	if state == "unavailable" then
		line = "Unavailable: " .. (needs[#needs] and not needs[#needs].met and needs[#needs].text or "a requirement is missing")
		for _, n in ipairs(needs) do
			if not n.met then
				line = "Unavailable: " .. n.text
				break
			end
		end
	elseif estimated > 0 then
        state="none";line=format(key=="craftde" and "%d estimated crafts" or "%d estimated purchase lots",estimated)
	elseif state == "missing" then
		line = "Missing data: "
		for _, n in ipairs(needs) do
			if not n.met then
				line = line .. n.text
				break
			end
		end
	elseif verified > 0 then
		line = format("%d verified opportunit%s", verified, verified > 1 and "ies" or "y")
	elseif #rows > 0 then
		state = "none"
		line = format("No verified opportunity (%d to review)", #rows)
	else
		state = "none"
		line = "No opportunity right now"
	end
	return { state = state, verified = verified, total = #rows, line = line, needs = needs }
end

function Eco.VerifiedOpportunities()
	local n = 0
	for _, m in ipairs(METHODS) do
		local s = Eco.MethodSummary(m.key)
		n = n + s.verified
	end
	return n
end

------------------------------------------------------------------------
-- Sheets: what to buy, what to do, the expected outcome
------------------------------------------------------------------------

local function NameOf(id, link)
	local it = (link and Item(link)) or Item(id)
	return it and it.name or ("item " .. tostring(id)), it
end

local Sheet = {}

function Sheet.resell(row)
	local d = row.d
	local name, it = NameOf(d.id, d.link)
	local s = { buy = {}, todo = {}, outcome = {}, fees = {}, assumptions = {}, search = { name } }
	local n = d.buy > 0 and d.buy or d.units
	s.buy[1] = { id = d.id, link = d.link or (it and it.link), name = name, qty = n, max = d.maxBuy, total = d.buy > 0 and d.cost or d.dealCost }
	s.total = s.buy[1].total
	s.who = "Any of your characters at this auction house"
	if d.status == "vendor" then
		s.todo = { format("Search \"%s\" at the auction house.", name), format("Buy up to %d at %s or less each (the vendor pays %s).", n, Money(d.maxBuy), Money(d.resell)), "Sell them to any vendor." }
		s.outcome = { { "Vendor pays", Money(d.resell) .. " each" }, { "Estimated net profit", Eco.ProfitText(d.profit > 0 and d.profit or d.potential) } }
		s.fees = { "No auction house cut: sold to a vendor" }
		s.assumptions = { "The auctions are still there at these prices (seen in the last scan).", "The vendor price is fixed by the game." }
	else
		s.todo = {
			format("Search \"%s\" at the auction house.", name),
			format("Buy %d at %s or less each (max price).", n, Money(d.maxBuy)),
			format("Post them at about %s each, the prudent resale price.", Money(d.resell)),
		}
		s.outcome = {
			{ "Prudent resale price", Money(d.resell) .. " each" },
			{ "After the cut and the deposits", Money(d.resell * (1 - Eco.cut) - (d.F or 0)) .. " each" },
			{ "Estimated net profit", Eco.ProfitText(d.buy > 0 and d.profit or d.potential) },
			{ "If the price drops 10 %", Eco.ProfitText(d.stress) },
		}
		s.fees = { format("Auction house cut: %d %%", floor(Eco.cut * 100 + 0.5)), format("Deposits of failed posts: %s per unit%s", Money(d.F or 0), d.depositKnown and "" or " (estimate)") }
		s.assumptions = {
			"Prudent price: the lowest of the 14 day median, the first quartile of 7 days, your recent sales and the price left once the cheap auctions are bought.",
			format("Price history: %d days.", d.days or 0),
			d.exact and "The price left after buying is exact (full scan)." or "The price left after buying is not known: a full scan sees it.",
			"Your budget and your stock limit the quantity (settings).",
		}
		if d.buy == 0 then
			s.assumptions[#s.assumptions + 1] = "Nothing to buy now: risky, budget used or two days of your sales already held."
		end
	end
	return s
end

function Sheet.craft(row)
	local d = row.d
	local name = NameOf(d.id)
	local s = { buy = {}, todo = {}, outcome = {}, fees = {}, assumptions = {}, search = {} }
	local ids = {}
	for id in pairs(d.rc.r) do
		ids[#ids + 1] = id
	end
	sort(ids)
	local total = 0
	for _, id in ipairs(ids) do
		local qty = d.rc.r[id]
		local unit, src = Eco.UnitCost(id, qty, 0, { [d.id] = true })
		local rname, rit = NameOf(id)
		s.buy[#s.buy + 1] = { id = id, link = rit and rit.link, name = rname, qty = qty, max = unit, total = unit and unit * qty, note = src }
		total = unit and total + unit * qty or total
		if src == "ah" then
			s.search[#s.search + 1] = rname
		end
	end
	s.total = d.cost
	s.who = format("%s (%s)", ns.CharKey():match("^[^-]+"), d.prof)
	s.todo = { "Buy the materials (the auction house, a vendor, or crafted first).", format("Craft %s (%s).", name, d.prof),
		format("Post it at about %s.", Money(d.sell)) }
	s.outcome = { { "Sale after the cut", Money(d.net) }, { "Deposits of failed posts", Money(d.fees) }, { "Estimated net profit", Eco.ProfitText(d.profit) } }
	s.fees = { format("Auction house cut: %d %%", floor(Eco.cut * 100 + 0.5)), format("Deposits of %d failed posts", DB().settings.failures) }
	s.assumptions = { "Sale price: the lowest of the last scan, never above the usual one.", format("Listed now: %d.", d.listed or 0) }
	return s
end

-- Informational skill goals never enter the purchase planner.
function Eco.DEGoals(mode)
 local e, market = DB()
 local enchanter = e.enchanters[ns.CharKey()]
 local rank = enchanter and tonumber(enchanter.r)
 if not rank then return {}, "This character's Enchanting rank is not known. Open your profession." end
 local rows, groups, seen = {}, {}, {}
 for key, rec in pairs(market.items) do
  local id = BaseID(key)
  if rec.s == market.scanId and rec.m and not seen[id] then
   seen[id] = true
   local it = Item(id)
   local lot = it and Eco.DE.LotOf(it)
   if lot and it.bind ~= 1 and not (Eco.DEExcluded and Eco.DEExcluded(id,it.link,it)) then
    local state, why, skill = Eco.DEState(it.link or id)
    local required = tonumber(skill) or lot.skill
    local nextSkill = required and required > rank and required <= rank + 25
    local atSkill = required and required <= rank and state == "unknown"
    if state ~= "no" and ((mode == "next" and nextSkill) or (mode == "check" and atSkill)) then
     local source = skill and "Client requirement" or "Classic threshold estimate; unverified on this client"
     local k = lot.key .. ":" .. required .. ":" .. source
     local row = groups[k]
     if not row then
      local delta = max(0, required-rank)
      row = {key="goal:"..mode..":"..k,method="de",goal=true,required=required,rank=rank,delta=delta,
       label=format("Enchanting %d (+%d) - %s",required,delta,lot.label),icon=lot.icon,itemQuality=lot.quality,
       quality=0,eligible=false,verified=false,reasons={source,"Eligibility and profitability must be checked before buying."},
       why=delta>0 and format("%d more Enchanting points needed; verify the client requirement.",delta) or "At your estimated skill range; the game has not confirmed disenchant eligibility.",
       examples={},d={modelReady=false}}
      groups[k]=row;rows[#rows+1]=row
     end
     if #row.examples < 5 then row.examples[#row.examples+1]=it.name end
    end
   end
  end
 end
 sort(rows,function(a,b) if a.required~=b.required then return a.required<b.required end return a.key<b.key end)
 return rows, format("Enchanting %d - %s - last scan; goals are not shopping lists",rank,mode=="next" and "next 25 skill points" or "candidates to verify")
end

function Sheet.de(row)
 if row.trade or row.bagItem or row.journal or row.excludedItem then return Eco.DEWorkflowSheet(row) end
 if row.goal then
  local todo = {}
  if row.delta > 0 then todo[#todo+1]=format("Raise Enchanting from %d to %d (+%d).",row.rank,row.required,row.delta) end
  todo[#todo+1]="Confirm the item's disenchant eligibility and skill requirement in game."
  todo[#todo+1]="Refresh the auction scan, then review Buy now for a priced purchase lot."
  return {buy={},search={},excluded={},todo=todo,outcome={{"Examples from the scan",table.concat(row.examples,", ")}},fees={},assumptions=row.reasons}
 end
 local d = row.d
	local s = { buy = {}, todo = {}, outcome = {}, fees = {}, assumptions = {}, search = {}, excluded = {} }
	local n = d.buy or 0
	for _, p in ipairs(Eco.LotPicked(d, n)) do
		local name, it = NameOf(BaseID(p.key), p.link)
		s.buy[#s.buy + 1] = { priceKey = p.key, id = BaseID(p.key), link = p.link or (it and it.link), name = name, qty = p.count, max = p.top, total = nil }
		s.search[#s.search + 1] = name
	end
	for _, b in ipairs(s.buy) do
		local sum = 0
		for i = 1, n do
			if d.offers[i][2] == b.priceKey then
				sum = sum + d.offers[i][1]
			end
		end
		b.total = sum
	end
	s.total = d.cost
	for _, entry in ipairs(d.excluded) do
		local name = NameOf(entry.id, entry.link)
		s.excluded[#s.excluded + 1] = { name = name, units = entry.units, state = entry.state, why = entry.why }
	end
	s.who = d.can and d.how or ("none: " .. tostring(d.how))
	s.todo = { "Buy the items listed, no more than their max price.", d.can and (d.how:find("mail") and ("Mail them to " .. d.how:match("^(%S+)") .. ".") or "Keep them on this character.") or "No enchanter of yours can disenchant them yet.",
		"Disenchant each item.", "Sell the materials at the auction house." }
	for _, res in ipairs(d.results) do
		local mname = NameOf(res[1])
		local v = Eco.MaterialValue(res[1])
		s.outcome[#s.outcome + 1] = { format("about %.1f x %s", n * res[2] * (res[3] + res[4]) / 2, mname), v and (Money(v) .. " each") or "no price" }
	end
	s.outcome[#s.outcome + 1] = { "Estimated net profit (model)", Eco.ProfitText(d.profit) }
	if d.chance then
		s.model = format("Model chance of a profit: %d %% - computed under the model's assumptions, not a guarantee.", floor(d.chance * 100))
	end
	s.fees = { format("Auction house cut on the materials: %d %%", floor(Eco.cut * 100 + 0.5)) }
	s.assumptions = {
		d.validated and "Yield table validated on this client." or "Yield table: the classic one, NOT validated on this client.",
		"Material prices: the lowest of the last scan, never above the usual one.",
		"Every auction listed is still there at its price.",
	}
	return s
end

function Sheet.craftde(row)
	local d = row.d
	local name = NameOf(d.id)
	local s = { buy = {}, todo = {}, outcome = {}, fees = {}, assumptions = {}, search = {} }
	local crafts = d.crafts or 1
	local list = Eco.ShoppingList(d.rc, crafts, d.own)
	local ids = {}
	for id in pairs(list.buy) do
		ids[#ids + 1] = id
	end
	sort(ids)
	for _, id in ipairs(ids) do
		local b = list.buy[id]
		local rname, rit = NameOf(id)
		s.buy[#s.buy + 1] = { id = id, link = rit and rit.link, name = rname, qty = b.qty, max = b.top, total = b.cost, note = b.src }
		if b.src == "ah" then
			s.search[#s.search + 1] = rname
		end
	end
	s.total = d.cost or d.one
	local o = d.o
	local how = o and ((o.deOk and o.how) or o.estHow)
	s.who = format("craft: %s (%s)%s", d.crafter.who, d.crafter.prof, how and ("; disenchant: " .. tostring(how)) or "")
	if d.level then
		s.todo = { "Buy the materials.", format("Craft %s (a skill point %s of the time).", name, d.points and format("%d %%", floor(d.points * 100 + 0.5)) or "?"),
			o and o.outlet == "de" and "Disenchant it, sell the materials." or "Sell it to a vendor." }
		s.outcome = { { "Net cost of a craft", Eco.ProfitText(d.net and -d.net) }, { "A skill point costs", Eco.ProfitText(d.perPoint and -d.perPoint) } }
	else
		s.todo = { "Buy the materials.", format("Craft %s x %d.", name, crafts * d.made), how and how:find("mail") and "Mail them to the enchanter." or "Keep them for the enchanter.",
			"Disenchant them.", "Sell the materials." }
		if d.unconfirmed then
			table.insert(s.todo, 1, format("Craft ONE %s first and check that Disenchant accepts it: the game has not confirmed it.", name))
		end
		s.outcome = { { "Materials, one craft", d.one and Money(d.one) or "Not all to be had" }, { "Disenchanted, one craft (estimate)", Money(d.value) },
			{ "Estimated net profit (model)", Eco.ProfitText(d.profit) } }
		if d.ret then
			s.outcome[#s.outcome + 1] = { "Return on the materials", format("%.1f%%", d.ret * 100) }
		end
		if o and o.ah then
			s.outcome[#s.outcome + 1] = { d.whole and "Sold whole instead: MORE, if it sells" or "Sold whole instead (after the cut)", Money(o.ah * d.made) }
		end
		if o then
			s.outcome[#s.outcome + 1] = { "Sold to a vendor instead", Money(o.vendor * d.made) }
		end
		if d.chance then
			s.model = format("Model chance of a profit: %d %% - computed under the model's assumptions, not a guarantee.", floor(d.chance * 100))
		end
	end
	s.fees = { format("Auction house cut on the materials: %d %%", floor(Eco.cut * 100 + 0.5)) }
	s.assumptions = { o and o.estimate and "Yield table: the classic one, NOT validated on this client." or "Yield table validated on this client.",
		"Material prices of the last scan; the cheap ones go first." }
	return s
end

-- the sheet of an opportunity, its eligibility and data quality told apart
function Eco.OppSheet(row)
	local s = Sheet[row.method](row)
	s.eligibility = { ok = row.eligible, why = row.why, unknown = row.state == "unknown" }
	s.quality = { level = row.quality, label = QUALITY[row.quality], reasons = row.reasons }
	s.verified = row.verified
	return s
end

------------------------------------------------------------------------
-- Market: search, category, favourites
--   current  the lowest price of the last scan (listed now)
--   typical  the median of the daily prices of 14 days (5 days at least)
--   trend    the median of 3 days against the 14 day median
------------------------------------------------------------------------

function Eco.MarketRows(search, category, favorites)
	local e, r = DB()
	Eco.NewPass()
	local out, loading = {}, 0
	search = search and search:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
	for key, rec in pairs(r.items) do
		local id = BaseID(key)
		local fav = e.watch[key] == true
		if (not favorites or fav) and rec.m then
			local cat = Eco.Category(id)
			if category == nil or category == "all" or cat == category then
				local it = Item(rec.l or id)
				if not it and search ~= "" then
					loading = loading + 1
				elseif search == "" or (it and it.name:lower():find(search, 1, true)) then
					local ind = (rec.h or rec.hp) and Indicators(rec) or nil
					local current = rec.s == r.scanId
					local level = Eco.DataQuality(key)
					out[#out + 1] = {
						key = key, id = id, link = rec.l, fav = fav, rec = rec, ind = ind,
						current = current and rec.m or nil, typical = ind and ind.days14 and ind.days14 >= 5 and ind.m14 or nil,
						listed = current and (rec.q or 0) or nil, quick = current and r.lastMode == "quick",
						trend = ind and ind.trend, quality = level,
					}
				end
			end
		end
	end
	return out, loading
end

function Eco.ToggleFavorite(key)
	local watch = DB().watch
	watch[key] = not watch[key] or nil
end
