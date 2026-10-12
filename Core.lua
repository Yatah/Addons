--[[
	WC3 Console - core: namespace, protected calls, events, saved
	variables, modules.

	The HUD is a 3440 x 500 art strip at the bottom of the screen
	(MobaGeom.lua, art px: 1 px = 1 screen px on a 3440 px wide screen);
	ns.k turns art px into UI units (Layout.lua). Every module is a frame
	over its rect of the strip, its content placed in art px.

	Modules are secure frames (SecureFrameTemplate): secure action buttons
	and unit buttons are anchored to them (this client refuses to anchor a
	protected frame to a plain addon frame). Protected Blizzard frames that
	cannot be reparented are placed at an absolute position ("followers").
]]

local ADDON, ns = ...
_G.WC3Console = ns

local _G = _G
local pairs, ipairs, type, pcall, xpcall, tostring = pairs, ipairs, type, pcall, xpcall, tostring

ns.ART = [[Interface\AddOns\WC3Console\art\]]
ns.FONT = _G.STANDARD_TEXT_FONT or [[Fonts\FRIZQT__.TTF]]

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

-- values the game hides from addon code in combat (not comparable)
local issecretvalue = _G.issecretvalue
function ns.IsSecret(v)
	return issecretvalue ~= nil and issecretvalue(v) == true
end

-- a number addon code may read
function ns.Num(v)
	return type(v) == "number" and not ns.IsSecret(v)
end

function ns.Print(text)
	local chat = _G.DEFAULT_CHAT_FRAME or _G.ChatFrame1
	if chat then
		chat:AddMessage("|cffffd100WC3 Console:|r " .. tostring(text))
	end
end

-- bounded diagnostics, kept across /reload (/wc3c diagnostics)
function ns.RecordDiagnostic(kind, message, stack)
	if not ns.cdb then
		return
	end
	local list = ns.cdb.diagnostics or {}
	ns.cdb.diagnostics = list
	local last = list[#list]
	if last and last.kind == kind and last.message == message then
		last.count = (last.count or 1) + 1
		last.time = time()
		return
	end
	list[#list + 1] = { time = time(), kind = kind, message = message, stack = stack, count = 1 }
	if #list > 20 then
		table.remove(list, 1)
	end
end

-- Every step runs protected: an error is reported once, the rest goes on.
-- (xpcall passes the arguments: no closure per call, this runs for every
-- event)
ns.errors = {}
local seen = {}
local function Traceback(e)
	return tostring(e) .. "\n" .. (_G.debugstack and _G.debugstack(2, 4, 0) or "")
end

function ns.Try(label, fn, ...)
	local ok, err = xpcall(fn, Traceback, ...)
	if not ok then
		local text = label .. ": " .. tostring(err)
		if not seen[text] then
			seen[text] = true
			ns.RecordDiagnostic("lua", label, tostring(err))
			table.insert(ns.errors, text)
			if #ns.errors > 30 then
				table.remove(ns.errors, 1)
			end
			ns.Print("|cffff4040error|r " .. label .. ": " .. tostring(err):match("^[^\n]*"))
		end
	end
	return ok
end

-- protected changes out of combat only: the last request per key waits
-- for the end of the combat
local queue, order = {}, {}
function ns.RunOOC(key, fn)
	if InCombatLockdown() then
		if not queue[key] then
			order[#order + 1] = key
		end
		queue[key] = fn
		return false
	end
	fn()
	return true
end

local function FlushQueue()
	local list, pending = order, queue
	order, queue = {}, {}
	for _, key in ipairs(list) do
		local fn = pending[key]
		if fn then
			ns.RunOOC(key, function()
				ns.Try("queued " .. tostring(key), fn)
			end)
		end
	end
end

-- Bursts gathered on the next frame, out of Blizzard's call stack; the
-- last request wins. outOfCombat: waits for the end of the combat.
local deferred = {}
function ns.Defer(key, fn, outOfCombat)
	local pending = deferred[key]
	if pending then
		pending.fn, pending.outOfCombat = fn, outOfCombat
		return
	end
	pending = { fn = fn, outOfCombat = outOfCombat }
	deferred[key] = pending
	C_Timer.After(0, function()
		deferred[key] = nil
		local function Run()
			ns.Try("deferred " .. tostring(key), pending.fn)
		end
		if pending.outOfCombat then
			ns.RunOOC(key, Run)
		else
			Run()
		end
	end)
end

-- the parent of the frames taken off the screen
ns.hider = CreateFrame("Frame", "WC3C_Hider", UIParent)
ns.hider:Hide()

-- Frames of Blizzard's Edit Mode (player, target, bars, chat, minimap...)
-- replace SetPoint / ClearAllPoints / SetScale with code that records the
-- change in the Edit Mode manager. Called from an addon, that code runs
-- tainted and the manager spreads the taint to every frame it lays out.
-- Their base methods, kept by Blizzard, only move the frame: every frame of
-- the console is placed through these.
function ns.SetPoint(frame, ...)
	(frame.SetPointBase or frame.SetPoint)(frame, ...)
end

function ns.ClearAllPoints(frame)
	(frame.ClearAllPointsBase or frame.ClearAllPoints)(frame)
end

function ns.SetScale(frame, scale)
	(frame.SetScaleBase or frame.SetScale)(frame, scale)
end

function ns.Reparent(frame, parent)
	if frame and frame.SetParent and frame:GetParent() ~= parent then
		frame:SetParent(parent)
	end
end

-- is the mouse over this frame (whatever frame is on top)
function ns.MouseOver(frame)
	local ok, over = pcall(frame.IsMouseOver, frame)
	return ok and over and true or false
end

------------------------------------------------------------------------
-- Events
--   ns.On(event, fn)            fn(event, ...)
--   ns.OnUnit(event, unit, fn)  the same, for this unit only (the game
--                               filters: nameplates and raid units never
--                               reach the addon)
--   ns.Fire("WC3C_...", ...)    the console's own events
------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local handlers = {}

local function Dispatch(list, event, ...)
	for i = 1, #list do
		ns.Try(event, list[i], event, ...)
	end
end

function ns.On(event, fn)
	local list = handlers[event]
	if not list then
		if not event:find("^WC3C_") and not pcall(eventFrame.RegisterEvent, eventFrame, event) then
			return
		end
		list = {}
		handlers[event] = list
	end
	list[#list + 1] = fn
end

function ns.Fire(event, ...)
	local list = handlers[event]
	if list then
		Dispatch(list, event, ...)
	end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	Dispatch(handlers[event], event, ...)
end)

local unitFrames = {}
function ns.OnUnit(event, unit, fn)
	local f = unitFrames[unit]
	if not f then
		f = CreateFrame("Frame")
		f.handlers = {}
		f:SetScript("OnEvent", function(self, e, ...)
			Dispatch(self.handlers[e], e, ...)
		end)
		unitFrames[unit] = f
	end
	local list = f.handlers[event]
	if not list then
		if not pcall(f.RegisterUnitEvent, f, event, unit) then
			return false
		end
		list = {}
		f.handlers[event] = list
	end
	list[#list + 1] = fn
	return true
end

-- A protected action refused: recorded (/wc3c diagnostics), shown once per
-- action in the chat.
local announced = {}
local function Blocked(kind, addon, action)
	if addon ~= ADDON then
		return
	end
	local message = tostring(action or "unknown action")
	ns.RecordDiagnostic(kind, message, _G.debugstack and _G.debugstack(2, 12, 0) or "")
	if not announced[message] then
		announced[message] = true
		ns.Print("|cffff4040blocked|r " .. message .. " (/wc3c diagnostics)")
	end
end
ns.On("ADDON_ACTION_BLOCKED", Blocked)
ns.On("ADDON_ACTION_FORBIDDEN", Blocked)

------------------------------------------------------------------------
-- Saved variables and profiles
------------------------------------------------------------------------

ns.PROFILE_DEFAULTS = {
	theme = "original", -- artwork only; saved separately for each profile
	scale = 1, -- size of the HUD (1: the width of the screen)
	marginX = 0, -- room left on the sides of the screen (UI units)
	marginY = 0, -- room under the HUD
	modules = {},
}

local function CopyTable(t)
	if type(t) ~= "table" then
		return t
	end
	local c = {}
	for k, v in pairs(t) do
		c[k] = CopyTable(v)
	end
	return c
end

local function Fill(t, defaults)
	for k, v in pairs(defaults) do
		if t[k] == nil then
			t[k] = CopyTable(v)
		elseif type(v) == "table" and type(t[k]) == "table" then
			Fill(t[k], v)
		end
	end
end

-- settings of older versions are dropped
local function Prune(t, defaults, keep)
	for k in pairs(t) do
		if defaults[k] == nil and k ~= keep then
			t[k] = nil
		end
	end
end

function ns.CharKey()
	return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "")
end

function ns.ModuleDB(m)
	local mods = ns.p.modules
	if type(mods[m.key]) ~= "table" then
		mods[m.key] = {}
	end
	local d = mods[m.key]
	if d.enabled == nil then
		d.enabled = true
	end
	Fill(d, m.defaults)
	Prune(d, m.defaults, "enabled")
	m.db = d
	return d
end

function ns.SelectProfile(name, silent)
	if ns.initialized and not silent and InCombatLockdown() then
		ns.Print("Profile change queued until combat ends.")
		ns.RunOOC("select-profile", function() ns.SelectProfile(name, silent) end)
		return
	end
	local db = ns.db
	if type(db.profiles[name]) ~= "table" then
		db.profiles[name] = {}
	end
	ns.cdb.profile = name
	ns.profileName = name
	ns.p = db.profiles[name]
	Fill(ns.p, ns.PROFILE_DEFAULTS)
	Prune(ns.p, ns.PROFILE_DEFAULTS)
	for _, m in ipairs(ns.modules) do
		ns.ModuleDB(m)
	end
	if not silent then
		if ns.initialized then
			ns.Print("Profile changed; reloading outside combat to apply all modules.")
			ns.RunOOC("profile-reload", ReloadUI)
			return
		end
		ns.RequestLayout()
		ns.Print("profile |cffffffff" .. name .. "|r")
	end
end

local function InitDB()
	if type(_G.WC3ConsoleDB) ~= "table" then
		_G.WC3ConsoleDB = {}
	end
	if type(_G.WC3ConsoleCharDB) ~= "table" then
		_G.WC3ConsoleCharDB = {}
	end
	local db = _G.WC3ConsoleDB
	db.profiles = db.profiles or {}
	if not next(db.profiles) then
		db.profiles.Default = {}
	end
	ns.db = db
	ns.cdb = _G.WC3ConsoleCharDB
	local name = ns.cdb.profile
	if not db.profiles[name] then
		name = db.profiles.Default and "Default" or next(db.profiles)
	end
	ns.SelectProfile(name, true)
end

function ns.ProfileNames()
	local list = {}
	for k in pairs(ns.db.profiles) do
		list[#list + 1] = k
	end
	table.sort(list)
	return list
end

function ns.NewProfile(name, copyFrom)
	if not name or name == "" then
		return
	end
	local src = copyFrom and ns.db.profiles[copyFrom]
	ns.db.profiles[name] = src and CopyTable(src) or {}
	ns.SelectProfile(name)
end

function ns.DeleteProfile(name)
	if not ns.db.profiles[name] then
		return
	end
	ns.db.profiles[name] = nil
	if not next(ns.db.profiles) then
		ns.db.profiles.Default = {}
	end
	if ns.profileName == name then
		ns.SelectProfile(ns.db.profiles.Default and "Default" or next(ns.db.profiles))
	end
end

------------------------------------------------------------------------
-- Modules
--   key, label, order, level (frame level), strata
--   rect (art px, default ns.RECTS[key]), or Place(m): places its frame
--   defaults = { ... } its settings, settings = { { type = "toggle" |
--     "range", key, label, min, max, step } } (options window)
--   insecure = true: plain frame (no secure content)
--   Create(m) at login, Layout(m) out of combat
------------------------------------------------------------------------

ns.modules = {}
ns.moduleByKey = {}

function ns.RegisterModule(m)
	m.order = m.order or (#ns.modules + 1)
	m.defaults = m.defaults or {}
	m.rect = m.rect or (ns.RECTS and ns.RECTS[m.key])
	ns.modules[#ns.modules + 1] = m
	ns.moduleByKey[m.key] = m
	table.sort(ns.modules, function(a, b)
		return a.order < b.order
	end)
	return m
end

function ns.Enabled(key)
	local m = ns.moduleByKey[key]
	return m and m.frame and m.db.enabled and m or nil
end

local function CreateModuleFrame(m)
	local f = CreateFrame("Frame", "WC3C_" .. m.key, UIParent, (not m.insecure) and "SecureFrameTemplate" or nil)
	f:SetFrameStrata(m.strata or "LOW")
	f:SetFrameLevel(m.level or 10)
	f:SetSize(1, 1)
	ns.SetPoint(f, "BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
	f.module = m
	m.frame = f
end

function ns.LayoutModule(m)
	if not m.frame then
		return
	end
	if m.Place then
		m:Place()
	else
		ns.PlaceModule(m)
	end
	if m.Layout then
		ns.Try(m.key .. " layout", m.Layout, m)
	end
	ns.UpdateFollowers(m)
end

function ns.LayoutAll()
	if InCombatLockdown() then
		ns.RunOOC("layout", ns.LayoutAll)
		return
	end
	ns.ComputeScale()
	ns.RescaleFonts()
	for _, m in ipairs(ns.modules) do
		ns.Try(m.key .. " placement", ns.LayoutModule, m)
	end
	ns.Fire("WC3C_LAYOUT")
end

local layoutPending = false
function ns.RequestLayout()
	if layoutPending then
		return
	end
	layoutPending = true
	C_Timer.After(0, function()
		layoutPending = false
		ns.LayoutAll()
	end)
end

------------------------------------------------------------------------
-- Followers: protected Blizzard frames placed at an absolute position of
-- the HUD (art px x, y: their `point` there), placed again with the
-- layout of their module
------------------------------------------------------------------------

ns.followers = {}

function ns.Follow(m, frame, point, x, y)
	if not frame then
		return
	end
	local info = ns.followers[frame] or {}
	info.m, info.point, info.x, info.y = m, point, x, y
	ns.followers[frame] = info
	ns.PlaceFollower(frame, info)
end

-- (a frame given back to Blizzard: no longer placed)
function ns.Unfollow(frame)
	ns.followers[frame] = nil
end

function ns.PlaceFollower(frame, info)
	-- A queued placement must not reclaim a frame handed back to Edit Mode.
	if ns.followers[frame] ~= info then
		return
	end
	if frame:IsProtected() and InCombatLockdown() then
		ns.RunOOC(frame, function()
			ns.PlaceFollower(frame, info)
		end)
		return
	end
	local k = ns.k
	local fs = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
	info.busy = true
	ns.Try("follower placement", function()
		ns.ClearAllPoints(frame)
		ns.SetPoint(frame, info.point, UIParent, "BOTTOMLEFT", (ns.ox + info.x * k) / fs, (ns.oy + info.y * k) / fs)
	end)
	info.busy = false
end

function ns.UpdateFollowers(m)
	for frame, info in pairs(ns.followers) do
		if not m or info.m == m then
			ns.PlaceFollower(frame, info)
		end
	end
end

-- Placed again when Blizzard code moves the frame (Edit Mode layouts, UI
-- parent management), on the next frame
function ns.HookPosition(frame, fn, skip)
	if not frame or frame.wc3cHooked then
		return
	end
	frame.wc3cHooked = true
	local busy = false
	local function Reapply()
		if busy then
			return
		end
		busy = true
		ns.Try("reposition", fn)
		busy = false
	end
	local key = {} -- one pending callback per watched frame
	local function Changed()
		local info = ns.followers[frame]
		if busy or (info and info.busy) or (skip and skip()) then
			return
		end
		ns.Defer(key, Reapply, true)
	end
	for _, method in ipairs({ "SetPoint", "SetPointBase", "ClearAllPoints", "ClearAllPointsBase", "SetScale", "SetScaleBase", "SetParent" }) do
		if type(frame[method]) == "function" then
			hooksecurefunc(frame, method, Changed)
		end
	end
end

------------------------------------------------------------------------
-- Startup
------------------------------------------------------------------------

ns.On("ADDON_LOADED", function(_, name)
	if name == ADDON then
		InitDB()
	end
end)

ns.On("PLAYER_LOGIN", function()
	ns.ComputeScale()
	for _, m in ipairs(ns.modules) do
		if m.db.enabled then
			CreateModuleFrame(m)
			if m.Create then
				ns.Try(m.key .. " create", m.Create, m)
			end
		end
	end
	ns.Try("blizzard frames", ns.SetupBlizzard)
	ns.LayoutAll()
	ns.initialized = true
	ns.Fire("WC3C_READY")
	ns.Print("loaded, |cffffffff/wc3c|r: options (or the cogwheel in the corner of the chat).")
	if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("WIIIUI") then
		ns.Print("|cffff4040WIIIUI is enabled too: disable one of the two addons (AddOns list), they replace the same frames.|r")
	end
end)

for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED", "EDIT_MODE_LAYOUTS_UPDATED" }) do
	ns.On(event, function()
		if ns.initialized then
			ns.RequestLayout()
		end
	end)
end

-- Entering/leaving Edit Mode can relayout systems without a saved-layout event.
local function EditModeLayout()
	if ns.initialized then
		ns.RequestLayout()
	end
end
if EventRegistry and EventRegistry.RegisterCallback then
	EventRegistry:RegisterCallback("EditMode.Enter", EditModeLayout, ns)
	EventRegistry:RegisterCallback("EditMode.Exit", EditModeLayout, ns)
end

ns.On("PLAYER_REGEN_ENABLED", FlushQueue)
