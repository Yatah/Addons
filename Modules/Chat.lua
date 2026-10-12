--[[
	WC3 Console - chat: the chat window over the translucent panel of the
	bottom right corner, its edit box in the gold box under it, the chat
	buttons above it (menu, channels: shown on mouse over the chat); a
	cogwheel in the corner (options), shown on mouse over.
]]

local _, ns = ...
local R = ns.R

local CHAT_BUTTONS = { "ChatFrameMenuButton", "ChatFrameChannelButton", "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton" }

-- a placer, run again on the next frame when Blizzard moves one of its
-- frames (not when it moves them itself)
local function Watch(frames, fn)
	local busy = false
	local function Place()
		busy = true
		ns.Try("chat layout", fn)
		busy = false
	end
	for _, frame in ipairs(frames) do
		hooksecurefunc(frame, "SetPoint", function()
			if not busy then
				ns.Defer(Place, Place, true)
			end
		end)
	end
	return Place
end

local function PlaceChat(m)
	ns.PlaceRect(_G.ChatFrame1, m, R.chatText)
end

local function PlaceEditBox(m)
	local e, i, k = _G.ChatFrame1EditBox, R.chatInput, ns.k
	ns.Place(e, m, i[1], i[2])
	ns.SetPoint(e, "BOTTOMRIGHT", m.frame, "BOTTOMLEFT", (i[1] + i[3] - m.rect[1]) * k, (i[2] - m.rect[2]) * k)
	e:SetHeight(i[4] * k)
end

local function PlaceButtons()
	local previous
	for _, name in ipairs(CHAT_BUTTONS) do
		local b = _G[name]
		if b then
			b:SetFrameStrata("HIGH")
			local h = b:GetHeight()
			ns.SetScale(b, (h and h > 0) and (22 / h) or 1)
			ns.ClearAllPoints(b)
			if previous then
				ns.SetPoint(b, "RIGHT", previous, "LEFT", -2, 0)
			else
				ns.SetPoint(b, "BOTTOMRIGHT", _G.ChatFrame1, "TOPRIGHT", 0, 2)
			end
			previous = b
		end
	end
end

-- buttons shown only while the mouse is over the chat panel (or them)
local function ShowOnHover(m, list)
	local watcher = CreateFrame("Frame", nil, m.frame)
	local elapsed = 0
	watcher:SetScript("OnUpdate", function(_, e)
		elapsed = elapsed + e
		if elapsed < 0.1 then
			return
		end
		elapsed = 0
		local over = ns.MouseOver(m.frame)
		for _, b in ipairs(list) do
			over = over or ns.MouseOver(b)
		end
		local alpha = over and 1 or 0
		for _, b in ipairs(list) do
			if b:GetAlpha() ~= alpha then
				b:SetAlpha(alpha)
			end
		end
	end)
	for _, b in ipairs(list) do
		b:SetAlpha(0)
	end
	return watcher
end

-- the chat windows over the HUD, without backgrounds
local function SetupChat(m)
	for i = 1, (_G.NUM_CHAT_WINDOWS or 10) do
		local cf = _G["ChatFrame" .. i]
		if cf then
			cf:SetFrameStrata("HIGH")
			local tab = _G["ChatFrame" .. i .. "Tab"]
			if tab then
				tab:SetFrameStrata("HIGH")
			end
			local edit = _G["ChatFrame" .. i .. "EditBox"]
			if edit then
				edit:SetFrameStrata("HIGH")
				for _, region in ipairs({ edit:GetRegions() }) do
					if region:GetObjectType() == "Texture" then
						region:SetAlpha(0)
					end
				end
			end
			if _G.FCF_SetWindowAlpha then
				pcall(_G.FCF_SetWindowAlpha, cf, 0)
			end
		end
	end
	for _, name in ipairs({ "GeneralDockManager", "ChatFrameMenuButton", "ChatFrameChannelButton" }) do
		if _G[name] then
			_G[name]:SetFrameStrata("HIGH")
		end
	end
	-- the side bar of the chat window is hidden, not the chat buttons it
	-- holds (menu, channels: placed above the chat by PlaceButtons, shown
	-- while the mouse is over the chat panel, as the cogwheel)
	local side, hover = _G.ChatFrame1ButtonFrame, {}
	for _, name in ipairs(CHAT_BUTTONS) do
		local b = _G[name]
		if b and side and b:GetParent() == side then
			ns.Reparent(b, UIParent)
			hover[#hover + 1] = b
		end
	end
	ns.Reparent(side, ns.hider)
	if #hover > 0 then
		m.buttonsHover = ShowOnHover(m, hover)
	end
	ns.Reparent(_G.QuickJoinToastButton, ns.hider)
	m.placeChat = Watch({ _G.ChatFrame1 }, function()
		PlaceChat(m)
	end)
	m.placeEdit = Watch({ _G.ChatFrame1EditBox }, function()
		PlaceEditBox(m)
	end)
	local buttons = {}
	for _, name in ipairs(CHAT_BUTTONS) do
		buttons[#buttons + 1] = _G[name]
	end
	m.placeButtons = Watch(buttons, PlaceButtons)
end

-- The cogwheel: above the chat window (nothing may take its clicks); the
-- corner is watched with IsMouseOver, whatever frame is under the mouse
local function NewCogwheel(m)
	local cog = CreateFrame("Button", "WC3C_Cogwheel", m.frame)
	cog:SetFrameStrata("HIGH")
	cog:SetFrameLevel(_G.ChatFrame1:GetFrameLevel() + 20)
	cog.icon = cog:CreateTexture(nil, "ARTWORK")
	cog.icon:SetAllPoints()
	cog.icon:SetTexture(ns.Other("cogwheel"))
	cog:SetHighlightTexture(ns.Other("cogwheel"), "ADD")
	cog:SetAlpha(0)
	cog:RegisterForClicks("AnyUp")
	cog:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("WC3 Console", 1, 0.82, 0)
		GameTooltip:AddLine("Click: options", 1, 1, 1)
		GameTooltip:Show()
	end)
	cog:SetScript("OnLeave", GameTooltip_Hide)
	cog:SetScript("OnClick", function()
		ns.Options.Toggle()
	end)
	m.cog = cog
	local zone = CreateFrame("Frame", nil, m.frame)
	local shown, elapsed = false, 0
	zone:SetScript("OnUpdate", function(_, e)
		elapsed = elapsed + e
		if elapsed < 0.1 then
			return
		end
		elapsed = 0
		local over = ns.MouseOver(zone) or ns.MouseOver(cog)
		if over ~= shown then
			shown = over
			cog:SetAlpha(over and 1 or 0)
		end
	end)
	m.cogZone = zone
end

ns.RegisterModule({
	key = "chat",
	label = "Chat",
	order = 45,
	level = 45,
	defaults = { dock = true },
	settings = {
		{ type = "toggle", key = "dock", label = "Chat window in the panel (reload)" },
	},
	Create = function(m)
		if m.db.dock then
			SetupChat(m)
		end
		NewCogwheel(m)
	end,
	Layout = function(m)
		if m.placeChat then
			m.placeChat()
			m.placeEdit()
			m.placeButtons()
		end
		local r = m.rect
		ns.PlaceRect(m.cog, m, R.cog)
		ns.Place(m.cogZone, m, r[1] + r[3] - 120, r[2] + r[4] - 60, 120, 60)
	end,
})
