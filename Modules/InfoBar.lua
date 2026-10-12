--[[
	WC3 Console - info bar (Titan Panel style, classic WoW 2004 look)
	A bar along the top of the screen: dark dialog background, the gold and
	stone border of the classic dialogs underneath, Friz Quadrata texts
	(gold labels, white values). Blocks ("plugins"), each with an icon, a
	label, a tooltip, click / mouse wheel actions:
	  left   WC3 Console, location + coordinates, experience, reputation, social
	  right  ammo, bags, durability, gold, performance, volume, clock
	and the LibDataBroker objects of the other addons.
	Right click on the bar: its options.
]]

local _, ns = ...
local floor, max, min, format = math.floor, math.max, math.min, string.format

local BAR = {}
ns.InfoBar = BAR
local plugins, byId = {}, {}
local GOLD = "|cffffd100"

local function Pct(v)
	if v >= 0.75 then
		return "|cff20ff20"
	elseif v >= 0.4 then
		return "|cffffff00"
	end
	return "|cffff2020"
end

local function Safe(fn, ...)
	local ok, a, b, c, d = pcall(fn, ...)
	if ok then
		return a, b, c, d
	end
end

local function Money(copper)
	copper = copper or 0
	if _G.GetCoinTextureString then
		local s = Safe(_G.GetCoinTextureString, copper, 11)
		if s then
			return s
		end
	end
	local g, s, c = floor(copper / 10000), floor(copper / 100) % 100, copper % 100
	return format("%d|TInterface\\MoneyFrame\\UI-GoldIcon:0|t %d|TInterface\\MoneyFrame\\UI-SilverIcon:0|t %d|TInterface\\MoneyFrame\\UI-CopperIcon:0|t", g, s, c)
end

--[[ plugin spec:
	id, label, icon, side ("LEFT" / "RIGHT"), order, default (shown)
	text(p) -> value text (the label is added by the bar)
	events = { ... } refresh on these events, interval = seconds
	tooltip(p, tt), click(p, button), wheel(p, delta)
]]
function BAR.Register(p)
	if byId[p.id] then
		return
	end
	p.side = p.side or "RIGHT"
	p.order = p.order or 50
	plugins[#plugins + 1] = p
	byId[p.id] = p
	table.sort(plugins, function(a, b)
		if a.side ~= b.side then
			return a.side < b.side
		end
		return a.order < b.order
	end)
	if BAR.m and BAR.m.frame then
		BAR.CreateButton(p)
		BAR.Refresh()
	end
end

------------------------------------------------------------------------
-- Built-in plugins
------------------------------------------------------------------------

BAR.Register({
	id = "wc3console", label = "WC3 Console", icon = ns.Other("cogwheel"), side = "LEFT", order = 1, noLabelText = true,
	text = function()
		return ""
	end,
	tooltip = function(_, tt)
		tt:AddLine("WC3 Console", 1, 0.82, 0)
		tt:AddLine("Click: options", 1, 1, 1)
		tt:AddLine("Right click: options of this bar", 1, 1, 1)
	end,
	click = function(p, button)
		if button == "RightButton" then
			BAR.ShowOptions(p.button)
		else
			ns.Options.Toggle()
		end
	end,
})

local function ZoneColor()
	local pvpType = GetZonePVPInfo and GetZonePVPInfo()
	if pvpType == "sanctuary" then
		return "|cff69ccf0"
	elseif pvpType == "arena" or pvpType == "hostile" then
		return "|cffff1a1a"
	elseif pvpType == "friendly" then
		return "|cff1aff1a"
	elseif pvpType == "contested" then
		return "|cffffb300"
	end
	return "|cffffd100"
end

local function Coords()
	if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then
		return
	end
	local map = Safe(C_Map.GetBestMapForUnit, "player")
	local pos = map and Safe(C_Map.GetPlayerMapPosition, map, "player")
	if pos and pos.GetXY then
		local x, y = pos:GetXY()
		if x and y and not ns.IsSecret(x) and (x > 0 or y > 0) then
			return x * 100, y * 100
		end
	end
end

BAR.Register({
	id = "location", label = "Loc", icon = [[Interface\Icons\INV_Misc_Map_01]], side = "LEFT", order = 10,
	events = { "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }, interval = 0.25,
	text = function()
		local zone = (GetMinimapZoneText and GetMinimapZoneText()) or ""
		local x, y = Coords()
		if x then
			return format("%s%s|r |cffffffff(%.1f, %.1f)|r", ZoneColor(), zone, x, y)
		end
		return ZoneColor() .. zone .. "|r"
	end,
	tooltip = function(_, tt)
		tt:AddLine(GetRealZoneText and GetRealZoneText() or "", 1, 1, 1)
		local sub = GetSubZoneText and GetSubZoneText() or ""
		if sub ~= "" then
			tt:AddLine(sub, 1, 0.82, 0)
		end
		local x, y = Coords()
		if x then
			tt:AddDoubleLine("Coordinates", format("%.1f, %.1f", x, y), 1, 0.82, 0, 1, 1, 1)
		end
		tt:AddLine(" ")
		tt:AddLine("Click: world map", 0.7, 0.7, 0.7)
	end,
	click = function()
		if ToggleWorldMap then
			ToggleWorldMap()
		end
	end,
})

BAR.Register({
	id = "xp", label = "XP", icon = [[Interface\Icons\INV_Misc_Book_09]], side = "LEFT", order = 20,
	events = { "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION", "PLAYER_ENTERING_WORLD" },
	text = function()
		if UnitLevel("player") >= ns.MaxLevel() then
			return "|cffffffffMax|r"
		end
		local cur, maxXP = UnitXP("player"), UnitXPMax("player")
		if type(maxXP) ~= "number" or maxXP <= 0 or ns.IsSecret(cur) then
			return ""
		end
		local rested = GetXPExhaustion() or 0
		local text = format("|cffffffff%.1f%%|r", cur / maxXP * 100)
		if rested > 0 then
			text = text .. format(" |cff4d85e6(+%.0f%%)|r", rested / maxXP * 100)
		end
		return text
	end,
	tooltip = function(_, tt)
		local cur, maxXP = UnitXP("player"), UnitXPMax("player")
		tt:AddLine(format("%s %d", LEVEL or "Level", UnitLevel("player")), 1, 1, 1)
		if type(maxXP) == "number" and maxXP > 0 then
			tt:AddDoubleLine("Experience", format("%d / %d", cur, maxXP), 1, 0.82, 0, 1, 1, 1)
			tt:AddDoubleLine("To level", tostring(maxXP - cur), 1, 0.82, 0, 1, 1, 1)
			tt:AddDoubleLine("Rested", tostring(GetXPExhaustion() or 0), 1, 0.82, 0, 0.3, 0.52, 0.9)
		end
	end,
})

-- (shared with the reputation bar of the player panel: Units.lua)
local WatchedFaction = ns.WatchedFaction

BAR.Register({
	id = "reputation", label = "Rep", icon = [[Interface\Icons\INV_Misc_Note_02]], side = "LEFT", order = 30,
	events = { "UPDATE_FACTION", "PLAYER_ENTERING_WORLD" },
	text = function()
		local name, standing, low, high, value = WatchedFaction()
		if not name then
			return "|cff808080-|r"
		end
		local label = _G["FACTION_STANDING_LABEL" .. (standing or 4)] or ""
		local c = FACTION_BAR_COLORS and FACTION_BAR_COLORS[standing or 4]
		local color = c and format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) or "|cffffffff"
		local pct = (high and low and high > low) and (value - low) / (high - low) * 100 or 0
		return format("|cffffffff%s|r %s%s %.0f%%|r", name, color, label, pct)
	end,
	tooltip = function(_, tt)
		local name, standing, low, high, value = WatchedFaction()
		if not name then
			tt:AddLine("No watched faction", 1, 1, 1)
			tt:AddLine("(Reputation panel: \"Show as experience bar\")", 0.7, 0.7, 0.7)
			return
		end
		tt:AddLine(name, 1, 1, 1)
		tt:AddDoubleLine(_G["FACTION_STANDING_LABEL" .. (standing or 4)] or "", format("%d / %d", value - low, high - low), 1, 0.82, 0, 1, 1, 1)
	end,
	click = function()
		if ToggleCharacter then
			pcall(ToggleCharacter, "ReputationFrame")
		end
	end,
})

BAR.Register({
	id = "social", label = "Social", icon = [[Interface\FriendsFrame\UI-Toast-FriendOnlineIcon]], side = "LEFT", order = 40,
	events = { "FRIENDLIST_UPDATE", "GUILD_ROSTER_UPDATE", "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE", "PLAYER_ENTERING_WORLD" },
	text = function()
		local friends = (C_FriendList and C_FriendList.GetNumOnlineFriends and Safe(C_FriendList.GetNumOnlineFriends)) or 0
		local text = format("|cffffffff%d|r", friends or 0)
		if IsInGuild and IsInGuild() and GetNumGuildMembers then
			local _, online = GetNumGuildMembers()
			text = text .. format(" |cff40ff40<%d>|r", online or 0)
		end
		return text
	end,
	tooltip = function(_, tt)
		tt:AddLine("Social", 1, 1, 1)
		local friends = (C_FriendList and C_FriendList.GetNumOnlineFriends and Safe(C_FriendList.GetNumOnlineFriends)) or 0
		tt:AddDoubleLine("Friends online", tostring(friends or 0), 1, 0.82, 0, 1, 1, 1)
		if IsInGuild and IsInGuild() and GetNumGuildMembers then
			local total, online = GetNumGuildMembers()
			tt:AddDoubleLine((GetGuildInfo and GetGuildInfo("player")) or "Guild", format("%d / %d", online or 0, total or 0), 1, 0.82, 0, 0.25, 1, 0.25)
		end
		tt:AddLine(" ")
		tt:AddLine("Click: friends list", 0.7, 0.7, 0.7)
	end,
	click = function()
		if ToggleFriendsFrame then
			pcall(ToggleFriendsFrame)
		end
	end,
})

-- right side ------------------------------------------------------------

BAR.Register({
	id = "ammo", label = "Ammo", icon = [[Interface\Icons\INV_Ammo_Arrow_02]], side = "RIGHT", order = 10, default = true,
	events = { "UNIT_INVENTORY_CHANGED", "BAG_UPDATE_DELAYED", "PLAYER_ENTERING_WORLD" },
	visible = function()
		local _, class = UnitClass("player")
		return class == "HUNTER" or GetInventoryItemTexture("player", 0) ~= nil
	end,
	text = function(p)
		local count = GetInventoryItemCount("player", 0) or 0
		local tex = GetInventoryItemTexture("player", 0)
		if tex then
			p.iconTexture:SetTexture(tex)
		end
		if not tex then
			return "|cffff2020none|r"
		end
		local color = count < 200 and "|cffff2020" or (count < 600 and "|cffffff00" or "|cffffffff")
		return color .. count .. "|r"
	end,
	tooltip = function(_, tt)
		local link = GetInventoryItemLink("player", 0)
		tt:AddLine("Ammo", 1, 1, 1)
		if link then
			tt:AddDoubleLine(link, tostring(GetInventoryItemCount("player", 0) or 0))
		else
			tt:AddLine("No ammo equipped", 1, 0.3, 0.3)
		end
	end,
})

local function BagSpace()
	local free, total = 0, 0
	local C = C_Container
	for bag = 0, 5 do
		local n = C and C.GetContainerNumSlots and Safe(C.GetContainerNumSlots, bag) or (GetContainerNumSlots and GetContainerNumSlots(bag)) or 0
		if n and n > 0 then
			local f = C and C.GetContainerNumFreeSlots and Safe(C.GetContainerNumFreeSlots, bag) or (GetContainerNumFreeSlots and GetContainerNumFreeSlots(bag)) or 0
			free, total = free + (f or 0), total + n
		end
	end
	return free, total
end

BAR.Register({
	id = "bags", label = "Bags", icon = [[Interface\Icons\INV_Misc_Bag_08]], side = "RIGHT", order = 20,
	events = { "BAG_UPDATE_DELAYED", "PLAYER_ENTERING_WORLD" },
	text = function()
		local free, total = BagSpace()
		local color = total > 0 and Pct(free / total * 2.5) or "|cffffffff"
		return format("%s%d|r|cffffffff/%d|r", color, free, total)
	end,
	tooltip = function(_, tt)
		local free, total = BagSpace()
		tt:AddLine("Bags", 1, 1, 1)
		tt:AddDoubleLine("Free slots", format("%d / %d", free, total), 1, 0.82, 0, 1, 1, 1)
		tt:AddLine(" ")
		tt:AddLine("Click: backpack", 0.7, 0.7, 0.7)
		tt:AddLine("Shift click: all bags", 0.7, 0.7, 0.7)
	end,
	-- (any left click: Blizzard's backpack button, see SecureBags)
	bags = "*",
})

local SLOT_NAMES = { [1] = "Head", [3] = "Shoulder", [5] = "Chest", [6] = "Waist", [7] = "Legs", [8] = "Feet", [9] = "Wrist", [10] = "Hands", [16] = "Main Hand", [17] = "Off Hand", [18] = "Ranged" }

local function Durability()
	local lowest, list = 1, {}
	for slot = 1, 18 do
		local cur, maxD = GetInventoryItemDurability(slot)
		if cur and maxD and maxD > 0 then
			local v = cur / maxD
			lowest = min(lowest, v)
			list[#list + 1] = { slot, v }
		end
	end
	return lowest, list
end

BAR.Register({
	id = "durability", label = "Durability", icon = [[Interface\Icons\Trade_BlackSmithing]], side = "RIGHT", order = 30,
	events = { "UPDATE_INVENTORY_DURABILITY", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_ENTERING_WORLD" },
	text = function()
		local v = Durability()
		return format("%s%d%%|r", Pct(v), floor(v * 100 + 0.5))
	end,
	tooltip = function(_, tt)
		local _, list = Durability()
		tt:AddLine("Durability", 1, 1, 1)
		for _, e in ipairs(list) do
			local name = SLOT_NAMES[e[1]] or ("Slot " .. e[1])
			tt:AddDoubleLine(name, format("%s%d%%|r", Pct(e[2]), floor(e[2] * 100 + 0.5)), 1, 0.82, 0)
		end
	end,
	click = function()
		if ToggleCharacter then
			pcall(ToggleCharacter, "PaperDollFrame")
		end
	end,
})

-- gold: this session, and every character of the account (saved)
BAR.Register({
	id = "gold", label = "Gold", icon = [[Interface\Icons\INV_Misc_Coin_01]], side = "RIGHT", order = 40,
	events = { "PLAYER_MONEY", "PLAYER_ENTERING_WORLD" },
	text = function()
		local money = GetMoney()
		BAR.startMoney = BAR.startMoney or money
		local db = ns.db
		db.gold = db.gold or {}
		local _, class = UnitClass("player")
		db.gold[ns.CharKey()] = { money = money, class = class }
		return "|cffffffff" .. Money(money) .. "|r"
	end,
	tooltip = function(_, tt)
		local money = GetMoney()
		local diff = money - (BAR.startMoney or money)
		tt:AddLine("Gold", 1, 1, 1)
		tt:AddDoubleLine("This session", (diff >= 0 and "|cff20ff20+|r" or "|cffff2020-|r") .. Money(math.abs(diff)), 1, 0.82, 0, 1, 1, 1)
		tt:AddLine(" ")
		local total = 0
		local names = {}
		for key in pairs(ns.db.gold or {}) do
			names[#names + 1] = key
		end
		table.sort(names)
		for _, key in ipairs(names) do
			local e = ns.db.gold[key]
			local c = e.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[e.class]
			tt:AddDoubleLine(key, Money(e.money or 0), c and c.r or 1, c and c.g or 1, c and c.b or 1, 1, 1, 1)
			total = total + (e.money or 0)
		end
		tt:AddLine(" ")
		tt:AddDoubleLine("Total", Money(total), 1, 0.82, 0, 1, 1, 1)
		if ns.Economy then
			tt:AddLine(" ")
			ns.Economy.TooltipLines(tt)
		end
		tt:AddLine("Click: economy window (auction house)", 0.7, 0.7, 0.7)
		tt:AddLine("Shift click: bags", 0.7, 0.7, 0.7)
		tt:AddLine("Right click: forget this character", 0.7, 0.7, 0.7)
	end,
	click = function(_, button)
		if button == "RightButton" and ns.db.gold then
			ns.db.gold[ns.CharKey()] = nil
		elseif ns.Economy and not IsShiftKeyDown() then
			ns.Economy.Toggle()
		end
	end,
	-- (shift click: Blizzard's backpack button, see SecureBags)
	bags = "shift-",
})

BAR.Register({
	id = "performance", label = "FPS", icon = [[Interface\Icons\INV_Gizmo_02]], side = "RIGHT", order = 50, interval = 1,
	text = function()
		local fps = GetFramerate() or 0
		local _, _, home, world = GetNetStats()
		local ms = max(home or 0, world or 0)
		local fc = fps >= 50 and "|cff20ff20" or (fps >= 25 and "|cffffff00" or "|cffff2020")
		local mc = ms <= 100 and "|cff20ff20" or (ms <= 250 and "|cffffff00" or "|cffff2020")
		return format("%s%d|r |cffffffff/|r %s%dms|r", fc, fps, mc, ms)
	end,
	tooltip = function(_, tt)
		local _, _, home, world = GetNetStats()
		tt:AddLine("Performance", 1, 1, 1)
		tt:AddDoubleLine("Framerate", format("%.0f fps", GetFramerate() or 0), 1, 0.82, 0, 1, 1, 1)
		tt:AddDoubleLine("Latency (home)", format("%d ms", home or 0), 1, 0.82, 0, 1, 1, 1)
		tt:AddDoubleLine("Latency (world)", format("%d ms", world or 0), 1, 0.82, 0, 1, 1, 1)
		-- memory of the addons (only when the tooltip is open)
		if UpdateAddOnMemoryUsage and C_AddOns and C_AddOns.GetNumAddOns then
			pcall(UpdateAddOnMemoryUsage)
			local list, total = {}, 0
			for i = 1, C_AddOns.GetNumAddOns() do
				local mem = GetAddOnMemoryUsage and GetAddOnMemoryUsage(i) or 0
				if mem > 0 then
					list[#list + 1] = { C_AddOns.GetAddOnInfo(i), mem }
					total = total + mem
				end
			end
			table.sort(list, function(a, b) return a[2] > b[2] end)
			tt:AddLine(" ")
			tt:AddDoubleLine("Addon memory", format("%.1f MB", total / 1024), 1, 0.82, 0, 1, 1, 1)
			for i = 1, min(8, #list) do
				tt:AddDoubleLine("  " .. tostring(list[i][1]), format("%.0f KB", list[i][2]), 0.8, 0.8, 0.8, 1, 1, 1)
			end
		end
	end,
})

local function Volume()
	return tonumber(GetCVar("Sound_MasterVolume")) or 1, GetCVar("Sound_EnableAllSound") ~= "0"
end

BAR.Register({
	id = "volume", label = "Vol", icon = [[Interface\Common\VoiceChat-Speaker]], side = "RIGHT", order = 60, default = false,
	events = { "CVAR_UPDATE" },
	text = function()
		local v, on = Volume()
		if not on then
			return "|cffff2020off|r"
		end
		return format("|cffffffff%d%%|r", floor(v * 100 + 0.5))
	end,
	tooltip = function(_, tt)
		tt:AddLine("Master volume", 1, 1, 1)
		tt:AddLine("Mouse wheel: volume", 0.7, 0.7, 0.7)
		tt:AddLine("Click: sound on / off", 0.7, 0.7, 0.7)
	end,
	wheel = function(_, delta)
		local v = Volume()
		SetCVar("Sound_MasterVolume", format("%.2f", max(0, min(1, v + delta * 0.05))))
	end,
	click = function()
		local _, on = Volume()
		SetCVar("Sound_EnableAllSound", on and "0" or "1")
	end,
})

BAR.Register({
	id = "clock", label = "Time", icon = [[Interface\Icons\INV_Misc_PocketWatch_01]], side = "RIGHT", order = 70, interval = 1,
	text = function(p)
		local h, mnt
		if BAR.m.db.serverTime and GetGameTime then
			h, mnt = GetGameTime()
		else
			local t = date("*t")
			h, mnt = t.hour, t.min
		end
		if BAR.m.db.clock24 then
			return format("|cffffffff%02d:%02d|r", h, mnt)
		end
		local suffix = h >= 12 and "PM" or "AM"
		h = h % 12
		if h == 0 then
			h = 12
		end
		return format("|cffffffff%d:%02d %s|r", h, mnt, suffix)
	end,
	tooltip = function(_, tt)
		tt:AddLine(date("%A %d %B %Y"), 1, 1, 1)
		tt:AddDoubleLine("Local time", date("%H:%M"), 1, 0.82, 0, 1, 1, 1)
		if GetGameTime then
			local h, mnt = GetGameTime()
			tt:AddDoubleLine("Server time", format("%02d:%02d", h, mnt), 1, 0.82, 0, 1, 1, 1)
		end
		tt:AddLine(" ")
		tt:AddLine("Click: calendar", 0.7, 0.7, 0.7)
	end,
	click = function()
		if ToggleCalendar then
			pcall(ToggleCalendar)
		elseif TimeManager_Toggle then
			pcall(TimeManager_Toggle)
		end
	end,
})

------------------------------------------------------------------------
-- LibDataBroker objects of the other addons
------------------------------------------------------------------------

local function AddBroker(name, obj)
	local id = "ldb:" .. name
	if byId[id] or type(obj) ~= "table" then
		return
	end
	BAR.Register({
		id = id, label = obj.label or name, broker = obj, side = "RIGHT", order = 5, default = obj.type ~= "launcher",
		icon = obj.icon,
		text = function(p)
			if obj.icon then
				p.iconTexture:SetTexture(obj.icon)
			end
			if obj.type == "launcher" then
				return ""
			end
			return "|cffffffff" .. tostring(obj.text or obj.value or "") .. "|r"
		end,
		tooltip = function(p, tt)
			if obj.OnTooltipShow then
				pcall(obj.OnTooltipShow, tt)
			else
				tt:AddLine(obj.label or name, 1, 1, 1)
			end
		end,
		enter = obj.OnEnter and function(p)
			pcall(obj.OnEnter, p.button)
			return true
		end,
		leave = obj.OnLeave and function(p)
			pcall(obj.OnLeave, p.button)
		end,
		click = obj.OnClick and function(p, button)
			pcall(obj.OnClick, p.button, button)
		end,
	})
end

function BAR.HookBrokers()
	local LibStub = _G.LibStub
	local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
	if not ldb or BAR.ldbHooked then
		return
	end
	BAR.ldbHooked = true
	for name, obj in ldb:DataObjectIterator() do
		AddBroker(name, obj)
	end
	ldb.RegisterCallback(BAR, "LibDataBroker_DataObjectCreated", function(_, name, obj)
		AddBroker(name, obj)
	end)
	ldb.RegisterCallback(BAR, "LibDataBroker_AttributeChanged", function(_, name)
		local p = byId["ldb:" .. name]
		if p then
			BAR.UpdatePlugin(p)
		end
	end)
end

------------------------------------------------------------------------
-- The bar
------------------------------------------------------------------------

local function PDB(p)
	local db = BAR.m.db.plugins
	local e = db[p.id]
	if type(e) ~= "table" then
		e = { shown = p.default ~= false, label = not p.noLabelText, icon = true }
		db[p.id] = e
	end
	return e
end

function BAR.Shown(p)
	if not PDB(p).shown then
		return false
	end
	if p.visible and not p.visible(p) then
		return false
	end
	return true
end

local function FontSize()
	return BAR.m.db.fontSize or 11
end

-- Bags opened from the bar: Blizzard's bag code must not run from this
-- addon's code. The bag frames make their item buttons on the first
-- opening; made from addon code, these buttons belong to the addon, and a
-- protected use of an item (a spell targeting it: disenchant, enchant...;
-- an item used in combat) is refused ("blocked from an action only
-- available to the Blizzard UI"). So a secure button over the block clicks
-- Blizzard's backpack button (click: the backpack; shift click: all bags,
-- as that button). It hangs on UIParent, placed out of combat: the bar stays
-- free to move in combat (a protected frame anchored to it would lock it).
local function PlaceSecure(p)
	local s, b = p.secure, p.button
	if not s then
		return
	end
	if InCombatLockdown() then
		ns.RunOOC("infobar-" .. p.id, function()
			PlaceSecure(p)
		end)
		return
	end
	local l, bottom, w, h = b:GetRect()
	if not (l and b:IsVisible()) then
		s:Hide()
		return
	end
	local k = b:GetEffectiveScale() / UIParent:GetEffectiveScale()
	s:ClearAllPoints()
	s:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l * k, bottom * k)
	s:SetSize(w * k, h * k)
	s:SetFrameStrata(b:GetFrameStrata())
	s:SetFrameLevel(b:GetFrameLevel() + 2)
	s:Show()
end

local function SecureBags(p)
	local b = p.button
	local s = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
	s:RegisterForClicks("AnyUp")
	s:SetAttribute("useOnKeyDown", false)
	s:SetAttribute(p.bags .. "type1", "click")
	s:SetAttribute("clickbutton", _G.MainMenuBarBackpackButton)
	local hl = s:CreateTexture(nil, "HIGHLIGHT")
	hl:SetTexture([[Interface\QuestFrame\UI-QuestTitleHighlight]])
	hl:SetBlendMode("ADD")
	hl:SetAllPoints()
	hl:SetAlpha(0.35)
	-- the block's tooltip, its other clicks
	s:SetScript("OnEnter", function()
		b:GetScript("OnEnter")(b)
	end)
	s:SetScript("OnLeave", function()
		b:GetScript("OnLeave")(b)
	end)
	s:SetScript("PostClick", function(_, button)
		if not (button == "LeftButton" and (p.bags == "*" or IsShiftKeyDown())) then
			b:GetScript("OnClick")(b, button)
		end
	end)
	-- (in the wrong place after a combat: hovering the block places it again)
	b:HookScript("OnEnter", function()
		PlaceSecure(p)
	end)
	b:HookScript("OnShow", function()
		PlaceSecure(p)
	end)
	b:HookScript("OnHide", function()
		PlaceSecure(p)
	end)
	p.secure = s
end

function BAR.CreateButton(p)
	local m = BAR.m
	local b = CreateFrame("Button", nil, m.frame)
	b:SetFrameLevel(m.frame:GetFrameLevel() + 3)
	b:RegisterForClicks("AnyUp")
	b:EnableMouseWheel(true)
	p.button = b
	p.iconTexture = b:CreateTexture(nil, "ARTWORK")
	p.iconTexture:SetTexture(p.icon)
	p.iconTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	p.fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	p.fs:SetJustifyH("LEFT")
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetTexture([[Interface\QuestFrame\UI-QuestTitleHighlight]])
	hl:SetBlendMode("ADD")
	hl:SetAllPoints()
	hl:SetAlpha(0.35)
	b:SetScript("OnEnter", function(self)
		if p.enter and p.enter(p) then
			return
		end
		local tt = GameTooltip
		tt:SetOwner(self, BAR.m.db.bottom and "ANCHOR_TOP" or "ANCHOR_BOTTOM")
		if p.tooltip then
			pcall(p.tooltip, p, tt)
		end
		tt:Show()
	end)
	b:SetScript("OnLeave", function()
		if p.leave then
			p.leave(p)
		end
		GameTooltip:Hide()
	end)
	b:SetScript("OnClick", function(_, button)
		if button == "RightButton" and not p.click then
			BAR.ShowOptions(b)
			return
		end
		if p.click then
			pcall(p.click, p, button)
			BAR.UpdatePlugin(p)
		end
	end)
	b:SetScript("OnMouseWheel", function(_, delta)
		if p.wheel then
			pcall(p.wheel, p, delta)
			BAR.UpdatePlugin(p)
		end
	end)
	if p.bags then
		ns.RunOOC("infobar-secure-" .. p.id, function()
			SecureBags(p)
			PlaceSecure(p)
		end)
	end
end

function BAR.UpdatePlugin(p)
	if not p.button then
		return
	end
	local e = PDB(p)
	local ok, value = pcall(p.text, p)
	value = ok and value or ""
	local label = ""
	if e.label and not p.noLabelText then
		label = GOLD .. p.label .. ":|r "
	end
	local text = label .. (value or "")
	if text ~= p.lastText then
		p.lastText = text
		p.fs:SetText(text)
		BAR.dirty = true
	end
end

function BAR.Layout()
	if InCombatLockdown() then
		ns.RunOOC("infobar-layout", BAR.Layout)
		return
	end
	local m = BAR.m
	if not m or not m.frame then
		return
	end
	local h = m.frame:GetHeight()
	local size = FontSize()
	local icon = min(h - 6, size + 5)
	local left, right = 8, 36 -- reserve the overflow menu at the right edge
	local gap = 14
	local available = max(0, m.frame:GetWidth() - 44)
	local hidden = {}
	if not m.overflow then
		local more = CreateFrame("Button", nil, m.frame)
		more:SetSize(24, h)
		more:SetPoint("RIGHT", m.frame, "RIGHT", -4, 0)
		more.text = more:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		more.text:SetAllPoints(); more.text:SetText("...")
		more:SetScript("OnClick", function() BAR.ShowOptions(more) end)
		more:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
			GameTooltip:AddLine("More information", 1, .82, 0)
			for _, plugin in ipairs(self.items or {}) do
				GameTooltip:AddLine(plugin.fs:GetText() or plugin.label or plugin.id, 1, 1, 1, true)
			end
			GameTooltip:AddLine("Click to choose visible blocks.", .8, .8, .8)
			GameTooltip:Show()
		end)
		more:SetScript("OnLeave", GameTooltip_Hide)
		m.overflow = more
	end
	for _, p in ipairs(plugins) do
		local b = p.button
		if b then
			local shown = BAR.Shown(p)
			b:SetShown(shown)
			if shown then
				local e = PDB(p)
				p.fs:SetFont(STANDARD_TEXT_FONT or ns.FONT, size, "")
				p.fs:SetShadowOffset(1, -1)
				p.iconTexture:SetShown(e.icon)
				p.iconTexture:SetSize(icon, icon)
				ns.ClearAllPoints(p.iconTexture)
				ns.SetPoint(p.iconTexture, "LEFT", b, "LEFT", 0, 0)
				ns.ClearAllPoints(p.fs)
				ns.SetPoint(p.fs, "LEFT", b, "LEFT", e.icon and (icon + 3) or 0, 0)
				local tw = p.fs:GetStringWidth() or 0
				local w = (e.icon and (icon + 3) or 0) + tw
				w = max(w, icon)
				b:SetSize(w, h)
				if w > available then
					b:Hide()
					hidden[#hidden + 1] = p
				else
				available = max(0, available - w - gap)
				ns.ClearAllPoints(b)
				if p.side == "LEFT" then
					ns.SetPoint(b, "LEFT", m.frame, "LEFT", left, 0)
					left = left + w + gap
				else
					ns.SetPoint(b, "RIGHT", m.frame, "RIGHT", -right, 0)
					right = right + w + gap
				end
				end -- enough room for this block
			end
		end
	end
	for _, p in ipairs(plugins) do
		PlaceSecure(p)
	end
	m.overflow.items = hidden
	m.overflow:SetShown(#hidden > 0)
	BAR.dirty = false
end

function BAR.Refresh()
	for _, p in ipairs(plugins) do
		if p.button then
			p.lastText = nil
			BAR.UpdatePlugin(p)
		end
	end
	BAR.Layout()
end

------------------------------------------------------------------------
-- Options of the bar (right click)
------------------------------------------------------------------------

function BAR.ShowOptions(anchor)
	local W = ns.W
	local f = BAR.options
	if not f then
		f = W.Panel("WC3C_InfoBarOptions", UIParent, 330, 100)
		f.title:SetText("Info bar")
		tinsert(UISpecialFrames, "WC3C_InfoBarOptions")
		BAR.options = f
	end
	for _, w in ipairs(f.widgets or {}) do
		w:Hide()
	end
	f.widgets = {}
	local m = BAR.m
	local y = -32
	local function Add(w, h, x)
		ns.SetPoint(w, "TOPLEFT", f, "TOPLEFT", x or 14, y)
		w:Show()
		f.widgets[#f.widgets + 1] = w
		if h then
			y = y - h
		end
	end
	local function Apply()
		ns.LayoutModule(m)
	end
	Add(W.Check(f, "Bottom of the screen", function() return m.db.bottom end, function(v) m.db.bottom = v Apply() end), 24)
	Add(W.Check(f, "Hide until the mouse comes to it", function() return m.db.autoHide end, function(v) m.db.autoHide = v end), 24)
	Add(W.Check(f, "24 hour clock", function() return m.db.clock24 end, function(v) m.db.clock24 = v BAR.Refresh() end), 0)
	Add(W.Check(f, "Server time", function() return m.db.serverTime end, function(v) m.db.serverTime = v BAR.Refresh() end), 24, 170)
	local fs = W.Slider(f, "Text size", 8, 16, 1, function() return m.db.fontSize end, function(v) m.db.fontSize = v Apply() end, "%d")
	fs:SetWidth(300)
	Add(fs, 40)
	local head = W.Label(f, "Blocks (shown / label / icon)", 12)
	head:SetTextColor(1, 0.82, 0)
	Add(head, 20)
	for _, p in ipairs(plugins) do
		local e = PDB(p)
		Add(W.Check(f, p.label, function() return e.shown end, function(v) e.shown = v BAR.Refresh() end), 0)
		Add(W.Check(f, "label", function() return e.label end, function(v) e.label = v BAR.Refresh() end), 0, 200)
		Add(W.Check(f, "icon", function() return e.icon end, function(v) e.icon = v BAR.Refresh() end), 22, 262)
	end
	f:SetHeight(-y + 12)
	for _, w in ipairs(f.widgets) do
		if w.Refresh then
			w:Refresh()
		end
	end
	ns.ClearAllPoints(f)
	ns.SetPoint(f, "CENTER", UIParent, "CENTER", 0, 0)
	f:Show()
end

------------------------------------------------------------------------
-- Module
------------------------------------------------------------------------

local HEIGHT = 28 -- UI units

ns.RegisterModule({
	key = "infobar",
	label = "Info bar",
	order = 90,
	level = 20,
	strata = "HIGH",
	insecure = true,
	defaults = { bottom = false, autoHide = false, clock24 = true, serverTime = false, fontSize = 12, plugins = {} },
	-- along the top (or bottom) edge of the screen
	Place = function(m)
		local f, point = m.frame, m.db.bottom and "BOTTOMLEFT" or "TOPLEFT"
		f:SetSize(UIParent:GetWidth(), HEIGHT)
		ns.ClearAllPoints(f)
		ns.SetPoint(f, point, UIParent, point, 0, 0)
	end,
	Create = function(m)
		BAR.m = m
		local f = m.frame
		f:EnableMouse(true)
		-- classic Titan Panel look: dark glossy gradient, a thin light line on
		-- the top edge, a dark line and a faint light one on the bottom edge
		m.back = CreateFrame("Frame", nil, f)
		m.back:SetFrameLevel(f:GetFrameLevel())
		m.back:SetAllPoints(f)
		local function Solid(layer, sub, r, g, b, a)
			local t = m.back:CreateTexture(nil, layer, nil, sub)
			t:SetTexture([[Interface\Buttons\WHITE8X8]])
			t:SetVertexColor(r, g, b, a)
			return t
		end
		m.bg = Solid("BACKGROUND", 0, 0.08, 0.08, 0.09, 0.92)
		m.bg:SetAllPoints(m.back)
		-- gloss: lighter top half fading to the dark bottom
		m.gloss = Solid("BACKGROUND", 1, 1, 1, 1, 0.08)
		if m.gloss.SetGradient and _G.CreateColor then
			pcall(m.gloss.SetGradient, m.gloss, "VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 0.13))
		end
		ns.SetPoint(m.gloss, "TOPLEFT", m.back, "TOPLEFT")
		ns.SetPoint(m.gloss, "TOPRIGHT", m.back, "TOPRIGHT")
		m.shade = Solid("BACKGROUND", 1, 0, 0, 0, 0.3)
		if m.shade.SetGradient and _G.CreateColor then
			pcall(m.shade.SetGradient, m.shade, "VERTICAL", CreateColor(0, 0, 0, 0.45), CreateColor(0, 0, 0, 0))
		end
		ns.SetPoint(m.shade, "BOTTOMLEFT", m.back, "BOTTOMLEFT")
		ns.SetPoint(m.shade, "BOTTOMRIGHT", m.back, "BOTTOMRIGHT")
		m.lineLight = Solid("BORDER", 0, 0.55, 0.55, 0.6, 0.55)
		m.lineDark = Solid("BORDER", 1, 0, 0, 0, 0.9)
		m.lineLow = Solid("BORDER", 0, 0.35, 0.35, 0.4, 0.4)
		for _, p in ipairs(plugins) do
			BAR.CreateButton(p)
		end
		-- right click on the bar: options
		f:SetScript("OnMouseUp", function(self, button)
			if button == "RightButton" then
				BAR.ShowOptions(self)
			end
		end)
		-- events of the plugins
		local seen = {}
		for _, p in ipairs(plugins) do
			for _, e in ipairs(p.events or {}) do
				seen[e] = seen[e] or {}
				table.insert(seen[e], p)
			end
		end
		for e, list in pairs(seen) do
			ns.On(e, function()
				for _, p in ipairs(list) do
					BAR.UpdatePlugin(p)
				end
			end)
		end
		-- 10 times a second: the timed blocks, the layout when a text
		-- changed width, the auto hide
		local acc, tick = {}, 0
		f:SetScript("OnUpdate", function(self, elapsed)
			tick = tick + elapsed
			if tick < 0.1 then
				return
			end
			elapsed, tick = tick, 0
			for _, p in ipairs(plugins) do
				if p.interval and p.button and p.button:IsShown() then
					acc[p] = (acc[p] or 0) + elapsed
					if acc[p] >= p.interval then
						acc[p] = 0
						BAR.UpdatePlugin(p)
					end
				end
			end
			if BAR.dirty then
				BAR.Layout()
			end
			local want = 1
			if m.db.autoHide then
				local over = ns.MouseOver(self)
				if not over then
					local _, cy = GetCursorPosition()
					cy = cy / UIParent:GetEffectiveScale()
					over = m.db.bottom and cy <= 4 or (not m.db.bottom and cy >= UIParent:GetHeight() - 4)
				end
				want = over and 1 or 0
			end
			if self:GetAlpha() ~= want then
				self:SetAlpha(want)
			end
		end)
		ns.On("WC3C_READY", BAR.HookBrokers)
		ns.On("PLAYER_ENTERING_WORLD", function()
			BAR.HookBrokers()
			BAR.Refresh()
		end)
	end,
	Layout = function(m)
		local h = m.frame:GetHeight()
		m.gloss:SetHeight(h * 0.55)
		m.shade:SetHeight(h * 0.5)
		-- light line on the screen side, dark + faint line on the inner side
		local outer, inner = "TOP", "BOTTOM"
		if m.db.bottom then
			outer, inner = "BOTTOM", "TOP"
		end
		local function Line(t, side, off, size)
			ns.ClearAllPoints(t)
			ns.SetPoint(t, side .. "LEFT", m.back, side .. "LEFT", 0, off)
			ns.SetPoint(t, side .. "RIGHT", m.back, side .. "RIGHT", 0, off)
			t:SetHeight(size)
		end
		Line(m.lineLight, outer, 0, 1)
		Line(m.lineDark, inner, 0, 2)
		Line(m.lineLow, inner, (inner == "BOTTOM") and -1 or 1, 1)
		BAR.Refresh()
	end,
})
