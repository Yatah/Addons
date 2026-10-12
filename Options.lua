--[[
	WC3 Console - options window (cogwheel in the corner of the chat, /wc3c)
	and slash commands
	  /wc3c                      options
	  /wc3c profile [name]       select (or create) a profile
	  /wc3c enable <module>      enable a module (after /reload)
	  /wc3c eco [...]            economy (auction house)
	  /wc3c errors, diagnostics  last errors, blocked actions
	  /wc3c auras                what this client gives for the target auras
	  /wc3c cdm                  where the viewers of the cooldown manager are
]]

local _, ns = ...
local floor, format = math.floor, string.format

_G.BINDING_HEADER_WC3CONSOLE = "WC3 Console"
_G.BINDING_NAME_WC3CONSOLE_OPTIONS = "Options"

------------------------------------------------------------------------
-- Widgets (also used by the info bar and the economy window)
------------------------------------------------------------------------

local W = {}
ns.W = W

function W.Label(parent, text, size)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	fs:SetFont(ns.FONT, size or 11, "")
	fs:SetShadowOffset(1, -1)
	fs:SetText(text or "")
	return fs
end

-- a movable dark panel with a gold edge and a title
function W.Panel(name, parent, w, h)
	local f = CreateFrame("Frame", name, parent or UIParent)
	f:SetSize(w, h)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.05, 0.04, 0.03, 0.92)
	for _, p in ipairs({ { "TOPLEFT", "TOPRIGHT", 0, 2 }, { "BOTTOMLEFT", "BOTTOMRIGHT", 0, 2 }, { "TOPLEFT", "BOTTOMLEFT", 2, 0 }, { "TOPRIGHT", "BOTTOMRIGHT", 2, 0 } }) do
		local t = f:CreateTexture(nil, "BORDER")
		t:SetColorTexture(0.75, 0.6, 0.25, 1)
		t:SetPoint(p[1])
		t:SetPoint(p[2])
		if p[3] > 0 then
			t:SetWidth(p[3])
		else
			t:SetHeight(p[4])
		end
	end
	f.title = W.Label(f, "", 14)
	f.title:SetPoint("TOP", 0, -8)
	f.title:SetTextColor(1, 0.82, 0)
	return f
end

function W.Button(parent, text, w, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(w or 90, 22)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	return b
end

function W.Check(parent, text, get, set)
	local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	c:SetSize(22, 22)
	c.label = W.Label(c, text, 11)
	c.label:SetPoint("LEFT", c, "RIGHT", 2, 0)
	c:SetScript("OnClick", function(self)
		set(self:GetChecked() and true or false)
	end)
	c.Refresh = function(self)
		self:SetChecked(get() and true or false)
	end
	return c
end

function W.Slider(parent, text, minV, maxV, step, get, set, fmt)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(220, 34)
	holder.label = W.Label(holder, text, 11)
	holder.label:SetPoint("TOPLEFT", 0, 0)
	holder.value = W.Label(holder, "", 11)
	holder.value:SetPoint("TOPRIGHT", 0, 0)
	local s = CreateFrame("Slider", nil, holder)
	s:SetOrientation("HORIZONTAL")
	s:SetHeight(14)
	s:SetPoint("BOTTOMLEFT", 0, 2)
	s:SetPoint("BOTTOMRIGHT", 0, 2)
	s:SetMinMaxValues(minV, maxV)
	s:SetValueStep(step)
	-- (the method of the game's sliders; OnValueChanged rounds to the step
	-- anyway when it is missing)
	if s.SetObeyStepOnDrag then
		s:SetObeyStepOnDrag(true)
	end
	s:EnableMouse(true)
	local track = s:CreateTexture(nil, "BACKGROUND")
	track:SetColorTexture(0.3, 0.25, 0.15, 1)
	track:SetPoint("LEFT")
	track:SetPoint("RIGHT")
	track:SetHeight(4)
	s:SetThumbTexture([[Interface\Buttons\UI-SliderBar-Button-Horizontal]])
	holder.slider = s
	local function Show(v)
		holder.value:SetText(format(fmt or "%.2f", v))
	end
	s:SetScript("OnValueChanged", function(_, v, user)
		v = floor(v / step + 0.5) * step
		Show(v)
		if user ~= false and not holder.refreshing then
			set(v)
		end
	end)
	holder.Refresh = function()
		holder.refreshing = true
		local v = get() or minV
		s:SetValue(v)
		Show(v)
		holder.refreshing = false
	end
	return holder
end

------------------------------------------------------------------------
-- Profiles
------------------------------------------------------------------------

local O = {}
ns.Options = O

local function Refresh()
	if O.frame and O.frame:IsShown() then
		for _, w in ipairs(O.frame.widgets) do
			w:Refresh()
		end
	end
end

local function ProfileMenu(anchor)
	local menu = O.profiles
	if not menu then
		menu = W.Panel("WC3C_ProfileMenu", UIParent, 220, 100)
		menu.title:SetText("Profiles")
		menu.rows = {}
		menu.input = CreateFrame("EditBox", nil, menu, "InputBoxTemplate")
		menu.input:SetSize(190, 20)
		menu.input:SetAutoFocus(false)
		menu.input:SetMaxLetters(32)
		local function Make(copy)
			local name = menu.input:GetText()
			if name and name ~= "" then
				ns.NewProfile(name, copy and ns.profileName)
				menu.input:SetText("")
				Refresh()
				ProfileMenu(anchor)
			end
		end
		menu.newB = W.Button(menu, "New", 60, function()
			Make(false)
		end)
		menu.copyB = W.Button(menu, "Copy", 60, function()
			Make(true)
		end)
		menu.delB = W.Button(menu, "Delete", 60, function()
			ns.DeleteProfile(ns.profileName)
			Refresh()
			ProfileMenu(anchor)
		end)
		tinsert(UISpecialFrames, "WC3C_ProfileMenu")
		O.profiles = menu
	end
	for _, r in ipairs(menu.rows) do
		r:Hide()
	end
	local y = -32
	for i, name in ipairs(ns.ProfileNames()) do
		local r = menu.rows[i]
		if not r then
			r = W.Button(menu, "", 190)
			menu.rows[i] = r
		end
		r:SetText((name == ns.profileName) and ("> " .. name .. " <") or name)
		r:SetScript("OnClick", function()
			ns.SelectProfile(name)
			Refresh()
			ProfileMenu(anchor)
		end)
		r:ClearAllPoints()
		r:SetPoint("TOP", menu, "TOP", 0, y)
		r:Show()
		y = y - 24
	end
	y = y - 6
	menu.input:ClearAllPoints()
	menu.input:SetPoint("TOP", menu, "TOP", 0, y)
	y = y - 26
	menu.newB:ClearAllPoints()
	menu.newB:SetPoint("TOPLEFT", menu, "TOPLEFT", 12, y)
	menu.copyB:ClearAllPoints()
	menu.copyB:SetPoint("TOP", menu, "TOP", 0, y)
	menu.delB:ClearAllPoints()
	menu.delB:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -12, y)
	menu:SetHeight(-y + 32)
	menu:ClearAllPoints()
	menu:SetPoint("TOP", anchor, "BOTTOM", 0, -4)
	menu:Show()
end

------------------------------------------------------------------------
-- Options window: the HUD and the modules on the left, the settings of
-- the modules on the right
------------------------------------------------------------------------

local function Apply(m)
	ns.RunOOC("options-" .. (m and m.key or "hud"), function()
		if m then
			ns.LayoutModule(m)
		else
			ns.LayoutAll()
		end
	end)
end

local function Build()
	local f = W.Panel("WC3C_Options", UIParent, 640, 100)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
	f.title:SetText("WC3 Console")
	tinsert(UISpecialFrames, "WC3C_Options") -- (Escape closes it)
	f.widgets = {}
	local x, y = 16, -34
	local function Add(w, h, dx)
		w:SetPoint("TOPLEFT", f, "TOPLEFT", x + (dx or 0), y)
		if w.Refresh then
			f.widgets[#f.widgets + 1] = w
		end
		y = y - h
	end
	local function Header(text)
		local fs = W.Label(f, text, 12)
		fs:SetTextColor(1, 0.82, 0)
		Add(fs, 20)
	end
	local function Slider(text, minV, maxV, step, key, fmt)
		local s = W.Slider(f, text, minV, maxV, step, function()
			return ns.p[key]
		end, function(v)
			ns.p[key] = v
			Apply()
		end, fmt)
		s:SetWidth(280)
		Add(s, 42)
	end

	-- left: the HUD, the modules
	Header("HUD")
	Slider("Size", 0.5, 1, 0.05, "scale", "%.2f")
	Slider("Screen margin, sides", 0, 60, 1, "marginX", "%d")
	Slider("Screen margin, bottom", 0, 80, 1, "marginY", "%d")
	Header("HUD Theme (artwork only; reload to apply)")
	for _, entry in ipairs({ { "original", "Original" }, { "wow_bronze", "WoW Bronze - Experimental" } }) do
		local key, label = entry[1], entry[2]
		local button = W.Button(f, label, 280, function()
			ns.p.theme = key
			for _, widget in ipairs(f.widgets) do widget:Refresh() end
			f.reload:Show()
		end)
		button.Refresh = function(self)
			local selected = (ns.p.theme == "wow_bronze" and "wow_bronze" or "original") == key
			self:SetText((selected and "[Selected] " or "") .. label)
		end
		Add(button, 26)
	end
	Header("Modules (a change needs a reload)")
	local col = 0
	for _, m in ipairs(ns.modules) do
		local c = W.Check(f, m.label, function()
			return m.db.enabled
		end, function(v)
			m.db.enabled = v
			f.reload:Show()
		end)
		Add(c, col == 1 and 24 or 0, col * 145)
		col = 1 - col
	end
	y = y - (col == 1 and 24 or 0) - 8
	f.reload = W.Button(f, "Reload the interface", 280, ReloadUI)
	Add(f.reload, 28)
	f.reload:Hide()
	local bar = W.Button(f, "Info bar...", 137, function()
		if ns.InfoBar.m and ns.InfoBar.m.frame then
			f:Hide()
			ns.InfoBar.ShowOptions()
		else
			ns.Print("enable the info bar module first (then reload).")
		end
	end)
	Add(bar, 0)
	local profiles = W.Button(f, "Profiles", 137, function(self)
		if O.profiles and O.profiles:IsShown() then
			O.profiles:Hide()
		else
			ProfileMenu(self)
		end
	end)
	Add(profiles, 28, 143)
	local left = y

	-- right: the settings of the modules
	x, y = 330, -34
	for _, m in ipairs(ns.modules) do
		if m.settings then
			Header(m.label)
			for _, s in ipairs(m.settings) do
				local function Get()
					return m.db[s.key]
				end
				local function Set(v)
					m.db[s.key] = v
					Apply(m)
				end
				if s.type == "range" then
					local w = W.Slider(f, s.label, s.min, s.max, s.step, Get, Set, s.step >= 1 and "%d" or "%.2f")
					w:SetWidth(280)
					Add(w, 40, 8)
				else
					Add(W.Check(f, s.label, Get, Set), 24, 4)
				end
			end
			y = y - 4
		end
	end
	f:SetHeight(-math.min(left, y) + 12)
	f:SetScript("OnShow", Refresh)
	f:Hide()
	O.frame = f
end

function O.Toggle()
	if not O.frame then
		Build()
	end
	O.frame:SetShown(not O.frame:IsShown())
end

function WC3Console_ToggleOptions()
	if ns.initialized then
		O.Toggle()
	end
end

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------

_G.SLASH_WC3CONSOLE1 = "/wc3c"
_G.SLASH_WC3CONSOLE2 = "/wc3console"
SlashCmdList.WC3CONSOLE = function(msg)
	if not ns.initialized then
		return
	end
	local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	cmd = cmd:lower()
	if cmd == "" or cmd == "options" or cmd == "config" then
		O.Toggle()
	elseif cmd == "profile" then
		if rest ~= "" then
			ns.SelectProfile(rest)
			Refresh()
		else
			ns.Print("profiles: " .. table.concat(ns.ProfileNames(), ", ") .. " (current: " .. ns.profileName .. ")")
		end
	elseif cmd == "enable" then
		local m = ns.moduleByKey[rest]
		if m then
			m.db.enabled = true
			ns.Print(m.label .. " enabled after /reload")
		end
	elseif cmd == "minimap" and ns.MinimapCommand then
		ns.MinimapCommand(rest)
	elseif (cmd == "eco" or cmd == "economy") and ns.Economy then
		ns.Economy.Slash(rest)
	elseif cmd == "auras" then
		ns.AuraDebug()
	elseif cmd == "cdm" then
		ns.ViewerDebug()
	elseif cmd == "errors" then
		if #ns.errors == 0 then
			ns.Print("no error.")
		end
		for _, e in ipairs(ns.errors) do
			ns.Print(e:match("^[^\n]*"))
		end
	elseif cmd == "diagnostics" then
		local list = ns.cdb.diagnostics or {}
		if #list == 0 then
			ns.Print("no recorded diagnostic.")
		end
		for _, e in ipairs(list) do
			ns.Print(date("%Y-%m-%d %H:%M:%S", e.time) .. " " .. e.kind .. ": " .. e.message .. " (" .. (e.count or 1) .. ")")
		end
	else
		ns.Print("/wc3c (options), /wc3c profile <name>, /wc3c enable <module>, /wc3c eco [scan|reset|purge|debug|classify|class <item>|de <item>], /wc3c errors, /wc3c diagnostics, /wc3c auras, /wc3c cdm")
	end
end
