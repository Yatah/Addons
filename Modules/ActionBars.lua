--[[
	WC3 Console - action bars
	  bar1       main bar, paged (stances, forms, vehicles...), keys
	             ACTIONBUTTON1-12: the big row (Dota's ability row)
	  bar2       actions 61-72, keys MULTIACTIONBAR1BUTTON1-12 (Blizzard's
	             bottom left bar), small row above it
	  bar3       actions 49-60, keys MULTIACTIONBAR2BUTTON1-12 (bottom right
	             bar), the top row
	  extrabars  two rows over the chat: actions 37-48 (keys
	             MULTIACTIONBAR4BUTTON1-12, Blizzard's left bar) and 25-36
	             (MULTIACTIONBAR3BUTTON1-12, right bar)
	The keys of Blizzard's bars click these buttons (override bindings).
]]

local _, ns = ...
local format = string.format
local R = ns.R

ns.buttons = {}

------------------------------------------------------------------------
-- Buttons
--
-- Our buttons are SecureActionButtonTemplate buttons that draw themselves.
-- Blizzard's ActionBarButtonTemplate is not used: made by an addon, its
-- OnLoad and every update sent to it wrote Blizzard's own fields
-- (self.action...) from addon code, and Blizzard's button code reading them
-- in combat ran tainted ("SetAttribute() blocked", UseAction refused).
-- Here Blizzard's code only does the click (SecureActionButton_OnClick,
-- from the attributes) and the drag and drop (secure snippets); every field
-- the addon writes is its own, read by its own code.
------------------------------------------------------------------------

local NATIVE = 45 -- (size of Blizzard's action buttons: ours are scaled from it)
local ICON_ZOOM = 0.167

local function NOPE() end
-- The action API of the client: C_ActionBar (Forever: the old globals only
-- exist there through Blizzard's deprecation wrappers, CVar
-- loadDeprecationFallbacks), else the old global
local CA = C_ActionBar or {}
local function API(name, global)
	return CA[name] or _G[global or name]
end
local HasAction, GetActionTexture = API("HasAction") or NOPE, API("GetActionTexture") or NOPE
local GetActionCount = API("GetActionUseCount", "GetActionCount") or NOPE
local GetActionDisplayCount, UsesActionText = CA.GetActionDisplayCount, CA.UsesActionText
local GetActionInfo, GetActionText = GetActionInfo, API("GetActionText") or NOPE
local IsUsableAction, IsCurrentAction = API("IsUsableAction") or NOPE, API("IsCurrentAction") or NOPE
local IsAutoRepeatAction, IsAttackAction = API("IsAutoRepeatAction") or NOPE, API("IsAttackAction") or NOPE
local IsEquippedAction, IsItemAction = API("IsEquippedAction") or NOPE, API("IsItemAction") or NOPE
local IsConsumableAction, IsStackableAction = API("IsConsumableAction") or NOPE, API("IsStackableAction") or NOPE
local IsActionInRange, GetMacroSpell = API("IsActionInRange"), _G.GetMacroSpell

-- Blizzard's buttons shown by the console (the pet bar): no frame art, the
-- icon cut
function ns.StripButton(b)
	local normal = b.GetNormalTexture and b:GetNormalTexture()
	if normal then
		normal:SetAlpha(0)
	end
	for _, key in ipairs({ "NormalTexture", "SlotArt", "SlotBackground", "FlyoutBorderShadow", "RightDivider", "BottomDivider" }) do
		if b[key] and b[key].SetAlpha then
			b[key]:SetAlpha(0)
		end
	end
	local icon = b.icon or (b:GetName() and _G[b:GetName() .. "Icon"])
	if icon then
		if b.IconMask and icon.RemoveMaskTexture then
			pcall(icon.RemoveMaskTexture, icon, b.IconMask)
		end
		local z = b.wc3cZoom or 0.08
		icon:SetTexCoord(z, 1 - z, z, 1 - z)
	end
end

local function UpdateHotkey(b)
	local hotkey = b.HotKey
	local key = GetBindingKey(b.commandName)
	if key then
		local ok, text = pcall(GetBindingText, key, true)
		hotkey:SetText(ok and text or key)
	else
		hotkey:SetText("")
	end
	hotkey:SetAlpha((b.action and HasAction(b.action)) and 1 or 0)
end

-- a plain boolean, nil when the game gives a secret value (not comparable)
local function Bool(v)
	if ns.IsSecret(v) then
		return nil
	end
	return v and true or false
end

-- the slot of a button, as the secure click computes it: its "action"
-- attribute, else its id on the page of its parent (bar1:
-- "useparent-actionpage", the page written by the attribute driver)
local function ActionOf(b)
	local action = tonumber(b:GetAttribute("action"))
	if action then
		return action
	end
	local id = b:GetID()
	if id and id > 0 then
		local page = tonumber(b:GetParent():GetAttribute("actionpage")) or 1
		return id + (page - 1) * 12
	end
end

local function ClearCooldown(cd)
	if cd.Clear then
		cd:Clear()
	else
		cd:SetCooldown(0, 0)
	end
end

-- In combat the cooldown values are secret for addon code: the duration
-- object of the action (made for addon code) when the game has one, else
-- the values while they are readable
local function UpdateCooldown(b)
	local cd, action = b.cooldown, b.action
	if not (action and HasAction(action)) then
		ClearCooldown(cd)
		return
	end
	local get = C_ActionBar and C_ActionBar.GetActionCooldownDuration
	if get and cd.SetCooldownFromDurationObject then
		local ok, duration = pcall(get, action)
		if ok and duration and pcall(cd.SetCooldownFromDurationObject, cd, duration) then
			return
		end
	end
	local start, duration, enable, modRate
	if CA.GetActionCooldown then
		local info = CA.GetActionCooldown(action)
		if info then
			start, duration, enable, modRate = info.startTime, info.duration, info.isEnabled, info.modRate
		end
	elseif _G.GetActionCooldown then
		start, duration, enable, modRate = _G.GetActionCooldown(action)
	end
	if ns.IsSecret(start) or ns.IsSecret(duration) or ns.IsSecret(enable) or ns.IsSecret(modRate) then
		ClearCooldown(cd)
	elseif enable and enable ~= 0 and type(duration) == "number" and duration > 0 then
		cd:SetCooldown(start, duration, modRate)
	else
		ClearCooldown(cd)
	end
end

-- checked (current / auto repeat), red flash of the auto attack / auto shot
local function UpdateState(b)
	local action = b.action
	if not (action and HasAction(action)) then
		b.checked:Hide()
		b.flashing = nil
		b.Flash:Hide()
		return
	end
	local current = Bool(IsCurrentAction(action))
	local autoRepeat = Bool(IsAutoRepeatAction(action))
	b.checked:SetShown(current == true or autoRepeat == true)
	b.flashing = ((current and Bool(IsAttackAction(action))) or autoRepeat) and true or nil
	if not b.flashing then
		b.Flash:Hide()
	end
end

-- icon colour: out of range (red), not enough mana (blue), unusable (grey)
local function UpdateUsable(b)
	local action, icon = b.action, b.icon
	if not (action and HasAction(action)) then
		icon:SetVertexColor(1, 1, 1)
		return
	end
	local usable, noMana = IsUsableAction(action)
	usable, noMana = Bool(usable), Bool(noMana)
	if b.outOfRange then
		icon:SetVertexColor(0.8, 0.1, 0.1)
	elseif usable ~= false then
		icon:SetVertexColor(1, 1, 1) -- (usable, or secret: shown as usable)
	elseif noMana then
		icon:SetVertexColor(0.5, 0.5, 1)
	else
		icon:SetVertexColor(0.4, 0.4, 0.4)
	end
end

local function UpdateRange(b)
	local action, out = b.action, nil
	if IsActionInRange and action and HasAction(action) then
		local ok, inRange = pcall(IsActionInRange, action)
		if ok and not ns.IsSecret(inRange) and (inRange == false or inRange == 0) then
			out = true
		end
	end
	if out ~= b.outOfRange then
		b.outOfRange = out
		UpdateUsable(b)
	end
end

-- the spell of an action (spell, or the spell of a macro): proc glows
local function ActionSpell(action)
	local kind, id = GetActionInfo(action)
	if kind == "spell" then
		return id
	elseif kind == "macro" and GetMacroSpell then
		return (GetMacroSpell(id))
	end
end

local function Overlayed(spell)
	local fn = (C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed) or _G.IsSpellOverlayed
	if not (spell and fn) then
		return false
	end
	local ok, on = pcall(fn, spell)
	return ok and Bool(on) == true
end

local function SetGlow(b, on)
	on = on and true or false
	if b.glowOn ~= on then
		b.glowOn = on
		b.glow:SetShown(on)
		if on then
			b.glowAnim:Play()
		else
			b.glowAnim:Stop()
		end
	end
end

-- stack of a consumable, reagents or charges of a spell (as Blizzard's
-- buttons: the text the game makes for the slot, "*" past 9999; a secret
-- value in combat, that a font string can show)
local function UpdateCount(b, action)
	local fs = b.Count
	if GetActionDisplayCount then
		local ok, text = pcall(GetActionDisplayCount, action)
		if not (ok and pcall(fs.SetText, fs, text)) then
			fs:SetText("")
		end
		return
	end
	local consumable = IsConsumableAction(action) or IsStackableAction(action)
	local count = GetActionCount(action)
	if ns.IsSecret(count) then
		if consumable then
			pcall(fs.SetText, fs, count)
		else
			fs:SetText("")
		end
	elseif consumable or (not IsItemAction(action) and (count or 0) > 0) then
		fs:SetText((count or 0) > 9999 and "*" or (count or 0))
	else
		fs:SetText("")
	end
end

-- the name shown on the button (a macro's): the game says when there is one
local function ActionName(action)
	local shown
	if UsesActionText then
		shown = Bool(UsesActionText(action))
	else
		shown = not (IsConsumableAction(action) or IsStackableAction(action))
	end
	return (shown and GetActionText(action)) or ""
end

-- everything the button shows (after a layout, a new page, a new action...)
local function RefreshButton(b)
	local action = ActionOf(b)
	b.action = action
	if action and HasAction(action) then
		b.icon:SetTexture(GetActionTexture(action))
		b.icon:Show()
		UpdateCount(b, action)
		b.Name:SetText(ActionName(action))
		b.border:SetShown(Bool(IsEquippedAction(action)) == true)
		b.spell = ActionSpell(action)
	else
		b.icon:Hide()
		b.Count:SetText("")
		b.Name:SetText("")
		b.border:Hide()
		b.spell = nil
	end
	SetGlow(b, b.spell and Overlayed(b.spell))
	b.outOfRange = nil
	UpdateState(b)
	UpdateUsable(b)
	UpdateCooldown(b)
	UpdateHotkey(b)
end

-- what changes often (cooldowns, usable, checked)
local function LightRefresh(b)
	UpdateState(b)
	UpdateUsable(b)
	UpdateCooldown(b)
end

local function ShowTooltip(self)
	local action = self.action
	if not (action and HasAction(action)) then
		return
	end
	if GetCVar("UberTooltips") == "1" and GameTooltip_SetDefaultAnchor then
		GameTooltip_SetDefaultAnchor(GameTooltip, self)
	else
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	end
	GameTooltip:SetAction(action)
	GameTooltip:Show()
end

------------------------------------------------------------------------
-- Drag and drop: secure snippets (restricted environment) return the slot
-- to pick up; Blizzard's secure handler picks it up / places the cursor
-- content there. (PickupAction / PlaceAction called from addon code would
-- put a tainted action on the cursor.)
------------------------------------------------------------------------

local dragHeader = CreateFrame("Frame", "WC3C_ActionDragHeader", UIParent, "SecureHandlerBaseTemplate")

-- the slot, as ActionOf (in the restricted environment)
local SLOT = [[
	local slot = self:GetAttribute("action")
	if not slot then
		local parent = self:GetParent()
		local page = tonumber(parent and parent:GetAttribute("actionpage")) or 1
		slot = self:GetID() + (page - 1) * 12
	end
]]
local DRAG_START = SLOT .. [[
	if self:GetAttribute("wc3cLocked") and not IsModifiedClick("PICKUPACTION") then
		return false
	end
	return "action", slot
]]
local RECEIVE_DRAG = SLOT .. [[
	return "action", slot
]]

-- "Lock action bars" (interface options): dragging an action off needs the
-- pick up modifier (shift), read by the drag snippet
local function Locked()
	local ok, on = pcall(GetCVarBool, "lockActionBars")
	return (ok and on) and true or false
end

local function UpdateLock()
	local locked = Locked()
	for _, b in ipairs(ns.buttons) do
		b:SetAttribute("wc3cLocked", locked)
	end
end

------------------------------------------------------------------------
-- What the buttons show follows the game's events. The updates of a frame
-- are gathered and made once, for the visible buttons (a button shown
-- again is refreshed then).
------------------------------------------------------------------------

local FULL = {
	PLAYER_ENTERING_WORLD = true, ACTIONBAR_SLOT_CHANGED = true, ACTIONBAR_PAGE_CHANGED = true,
	UPDATE_BONUS_ACTIONBAR = true, UPDATE_SHAPESHIFT_FORM = true, UPDATE_SHAPESHIFT_FORMS = true,
	UPDATE_MACROS = true, SPELLS_CHANGED = true, LEARNED_SPELL_IN_SKILL_LINE = true, PLAYER_EQUIPMENT_CHANGED = true,
	BAG_UPDATE_DELAYED = true, UPDATE_INVENTORY_ALERTS = true, UNIT_INVENTORY_CHANGED = true,
	SPELL_UPDATE_CHARGES = true, SPELL_UPDATE_ICON = true,
}
local LIGHT = {
	"ACTIONBAR_UPDATE_STATE", "ACTIONBAR_UPDATE_USABLE", "ACTIONBAR_UPDATE_COOLDOWN", "SPELL_UPDATE_COOLDOWN",
	"SPELL_UPDATE_USABLE", "ACTION_USABLE_CHANGED", "PLAYER_TARGET_CHANGED", "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE",
	"START_AUTOREPEAT_SPELL", "STOP_AUTOREPEAT_SPELL", "PLAYER_ENTER_COMBAT", "PLAYER_LEAVE_COMBAT",
	"LOSS_OF_CONTROL_ADDED", "LOSS_OF_CONTROL_UPDATE", "UPDATE_SUMMONPETS_ACTION", "COMPANION_UPDATE",
}
local GLOW = { SPELL_ACTIVATION_OVERLAY_GLOW_SHOW = true, SPELL_ACTIVATION_OVERLAY_GLOW_HIDE = true }

local updater = CreateFrame("Frame")
local pending -- nil, "light" or "full"
for event in pairs(FULL) do
	if event == "UNIT_INVENTORY_CHANGED" then
		pcall(updater.RegisterUnitEvent, updater, event, "player")
	else
		pcall(updater.RegisterEvent, updater, event)
	end
end
for _, event in ipairs(LIGHT) do
	pcall(updater.RegisterEvent, updater, event)
end
for event in pairs(GLOW) do
	pcall(updater.RegisterEvent, updater, event)
end
updater:RegisterEvent("CVAR_UPDATE")

updater:SetScript("OnEvent", function(_, event, arg1)
	if GLOW[event] then
		if ns.IsSecret(arg1) then
			return
		end
		for _, b in ipairs(ns.buttons) do
			if b.spell and b.spell == arg1 then
				SetGlow(b, event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
			end
		end
	elseif event == "CVAR_UPDATE" then
		if type(arg1) == "string" and arg1:lower() == "lockactionbars" then
			ns.RunOOC("actionlock", UpdateLock)
		end
	elseif FULL[event] then
		pending = "full"
	elseif not pending then
		pending = "light"
	end
end)

local rangeTime, flashTime, flashOn = 0, 0, false
updater:SetScript("OnUpdate", function(_, elapsed)
	if pending then
		local fn = pending == "full" and RefreshButton or LightRefresh
		pending = nil
		for _, b in ipairs(ns.buttons) do
			if b:IsVisible() then
				ns.Try("action button", fn, b)
			end
		end
	end
	rangeTime = rangeTime + elapsed
	if rangeTime >= 0.2 then
		rangeTime = 0
		for _, b in ipairs(ns.buttons) do
			if b:IsVisible() then
				UpdateRange(b)
			end
		end
	end
	flashTime = flashTime + elapsed
	if flashTime >= 0.4 then
		flashTime = 0
		flashOn = not flashOn
		for _, b in ipairs(ns.buttons) do
			if b.flashing then
				b.Flash:SetShown(flashOn)
			end
		end
	end
end)

------------------------------------------------------------------------
-- Quick Keybind mode (hover a button, press a key). Blizzard's buttons tell
-- QuickKeybindFrame the command they bind (SetSelected) and pass it their
-- mouse buttons / wheel; ours are secure buttons without that code. While
-- the mode is on, a plain button covers each of them and does the same
-- (above Blizzard's bars; its clicks never reach the action: a mouse button
-- pressed there is bound, not cast).
------------------------------------------------------------------------

local QUICK_ATLAS = "UI-HUD-ActionBar-IconFrame-Mouseover"
local quickMode = false

local function QuickFrame()
	local f = _G.QuickKeybindFrame
	return f and f.SetSelected and f
end

-- the tooltip of Blizzard's buttons in that mode (QuickKeybindFrame calls
-- it again after each key: the method name is Blizzard's)
local function QuickTooltip(q)
	local tt = _G.QuickKeybindTooltip or GameTooltip
	local command = q.commandName
	tt:SetOwner(q, "ANCHOR_RIGHT")
	tt:AddLine((GetBindingName and GetBindingName(command)) or command, 1, 1, 1)
	local key = (GetBindingKeyForAction and GetBindingKeyForAction(command)) or GetBindingKey(command)
	if key then
		tt:AddLine((GetBindingText and GetBindingText(key)) or key, 0.1, 1, 0.1)
		tt:AddLine(_G.ESCAPE_TO_UNBIND or "Escape: unbind", 1, 0.82, 0)
	else
		tt:AddLine(_G.NOT_BOUND or "Not bound", 1, 0.1, 0.1)
		tt:AddLine(_G.PRESS_KEY_TO_BIND or "Press a key to bind it", 1, 0.82, 0)
	end
	tt:Show()
end

local function QuickOverlay(b)
	local q = CreateFrame("Button", nil, b)
	q:SetAllPoints(b)
	q:SetFrameStrata("HIGH")
	q:RegisterForClicks("AnyUp")
	q:EnableMouseWheel(true)
	q.commandName = b.commandName
	q.QuickKeybindButtonSetTooltip = QuickTooltip
	q.hl = q:CreateTexture(nil, "OVERLAY")
	q.hl:SetAllPoints(b)
	if ns.HasAtlas(QUICK_ATLAS) then
		q.hl:SetAtlas(QUICK_ATLAS)
	else
		q.hl:SetColorTexture(0.3, 0.6, 1, 0.6)
	end
	q.hl:SetAlpha(0.5)
	q:SetScript("OnEnter", function(self)
		local f = QuickFrame()
		if f then
			f:SetSelected(self.commandName, self)
			QuickTooltip(self)
		end
		self.hl:SetAlpha(1)
	end)
	q:SetScript("OnLeave", function(self)
		local f = QuickFrame()
		if f then
			f:SetSelected(nil, nil)
		end
		if _G.QuickKeybindTooltip then
			_G.QuickKeybindTooltip:Hide()
		end
		GameTooltip:Hide()
		self.hl:SetAlpha(0.5)
	end)
	-- (left / right clicks stay clicks, as on Blizzard's buttons)
	q:SetScript("OnClick", function(_, button)
		local f = QuickFrame()
		if f and button ~= "LeftButton" and button ~= "RightButton" then
			f:OnKeyDown(button)
		end
	end)
	q:SetScript("OnMouseWheel", function(_, delta)
		local f = QuickFrame()
		if f and f.OnMouseWheel then
			f:OnMouseWheel(delta)
		end
	end)
	q:SetShown(quickMode)
	return q
end

local function SetQuickMode(on)
	quickMode = on and true or false
	for _, b in ipairs(ns.buttons) do
		b.quick:SetShown(quickMode)
	end
end

-- the mode's own notifications, and its frame (loaded on demand) as a
-- fallback
if EventRegistry then
	EventRegistry:RegisterCallback("QuickKeybindFrame.QuickKeybindModeEnabled", function() SetQuickMode(true) end, ns.buttons)
	EventRegistry:RegisterCallback("QuickKeybindFrame.QuickKeybindModeDisabled", function() SetQuickMode(false) end, ns.buttons)
end
local quickHooked = false
local function HookQuickFrame()
	local f = _G.QuickKeybindFrame
	if f and not quickHooked then
		quickHooked = true
		f:HookScript("OnShow", function() SetQuickMode(true) end)
		f:HookScript("OnHide", function() SetQuickMode(false) end)
	end
end
ns.On("ADDON_LOADED", HookQuickFrame)

------------------------------------------------------------------------
-- Creation (out of combat: at login)
------------------------------------------------------------------------

-- action: the slot of the button; nil: its id (SetID) on the page of its
-- parent (bar1). command: the binding command of the Blizzard bar key that
-- clicks it.
local function NewButton(name, parent, action, command)
	local b = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
	b:SetSize(NATIVE, NATIVE)
	b:RegisterForClicks("AnyUp", "AnyDown")
	b:SetAttribute("type", "action")
	b:SetAttribute("checkselfcast", true)
	b:SetAttribute("checkfocuscast", true)
	b:SetAttribute("checkmouseovercast", true)
	if action then
		b:SetID(0)
		b:SetAttribute("action", action)
	else
		b:SetAttribute("useparent-actionpage", true)
	end
	b.commandName = command
	-- art (the cell of the HUD is under it)
	b.icon = b:CreateTexture(name .. "Icon", "BACKGROUND")
	b.icon:SetAllPoints(b)
	b.icon:SetTexCoord(ICON_ZOOM, 1 - ICON_ZOOM, ICON_ZOOM, 1 - ICON_ZOOM)
	b.Flash = b:CreateTexture(name .. "Flash", "ARTWORK")
	b.Flash:SetTexture([[Interface\Buttons\UI-QuickslotRed]])
	b.Flash:SetAllPoints(b)
	b.Flash:Hide()
	b.border = b:CreateTexture(nil, "OVERLAY")
	b.border:SetTexture([[Interface\Buttons\UI-ActionButton-Border]])
	b.border:SetBlendMode("ADD")
	b.border:SetVertexColor(0, 1, 0, 0.5)
	b.border:SetSize(NATIVE * 1.72, NATIVE * 1.72)
	ns.SetPoint(b.border, "CENTER", b, "CENTER", 0, 0)
	b.border:Hide()
	b:SetPushedTexture([[Interface\Buttons\UI-Quickslot-Depress]])
	b:SetHighlightTexture([[Interface\Buttons\ButtonHilight-Square]], "ADD")
	b.cooldown = CreateFrame("Cooldown", name .. "Cooldown", b, "CooldownFrameTemplate")
	b.cooldown:SetAllPoints(b)
	b.cooldown:SetHideCountdownNumbers(true)
	ns.MaskIcon(b, b.icon)
	-- over the cooldown: checked, proc glow
	local over = CreateFrame("Frame", nil, b)
	over:SetAllPoints(b)
	b.overlay = over
	b.checked = over:CreateTexture(nil, "ARTWORK")
	b.checked:SetTexture([[Interface\Buttons\CheckButtonHilight]])
	b.checked:SetBlendMode("ADD")
	b.checked:SetAllPoints(b)
	b.checked:Hide()
	b.glow = over:CreateTexture(nil, "OVERLAY")
	b.glow:SetTexture([[Interface\Buttons\UI-ActionButton-Border]])
	b.glow:SetBlendMode("ADD")
	b.glow:SetVertexColor(1, 0.8, 0.25, 1)
	b.glow:SetSize(NATIVE * 1.9, NATIVE * 1.9)
	ns.SetPoint(b.glow, "CENTER", b, "CENTER", 0, 0)
	b.glow:Hide()
	b.glowAnim = b.glow:CreateAnimationGroup()
	b.glowAnim:SetLooping("BOUNCE")
	local pulse = b.glowAnim:CreateAnimation("Alpha")
	pulse:SetFromAlpha(0.3)
	pulse:SetToAlpha(1)
	pulse:SetDuration(0.5)
	-- the texts over the frame of the bar (see PlaceButton)
	local texts = CreateFrame("Frame", nil, b)
	texts:SetAllPoints(b)
	texts:EnableMouse(false)
	b.texts = texts
	b.HotKey = texts:CreateFontString(name .. "HotKey", "OVERLAY", "NumberFontNormalSmallGray")
	b.HotKey:SetJustifyH("RIGHT")
	b.HotKey:SetSize(NATIVE - 4, 12)
	ns.SetPoint(b.HotKey, "TOPRIGHT", b, "TOPRIGHT", -2, -3)
	b.Count = texts:CreateFontString(name .. "Count", "OVERLAY", "NumberFontNormal")
	b.Count:SetJustifyH("RIGHT")
	ns.SetPoint(b.Count, "BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
	b.Name = texts:CreateFontString(name .. "Name", "OVERLAY", "GameFontHighlightSmallOutline")
	b.Name:SetSize(NATIVE - 2, 10)
	ns.SetPoint(b.Name, "BOTTOM", b, "BOTTOM", 0, 2)
	-- (scripts of our own: the click itself stays the template's)
	b:SetScript("OnEnter", ShowTooltip)
	b:SetScript("OnLeave", GameTooltip_Hide)
	b:SetScript("PostClick", UpdateState)
	b:HookScript("OnShow", RefreshButton)
	b:RegisterForDrag("LeftButton", "RightButton")
	SecureHandlerWrapScript(b, "OnDragStart", dragHeader, DRAG_START)
	SecureHandlerWrapScript(b, "OnReceiveDrag", dragHeader, RECEIVE_DRAG)
	b.quick = QuickOverlay(b)
	b:SetAttribute("wc3cLocked", Locked())
	ns.buttons[#ns.buttons + 1] = b
	return b
end

-- a button of `size` art px centred at x, y in module m; its texts over the
-- frame art of the bar (level + 3)
local function PlaceButton(b, m, x, y, size)
	local k, level = ns.k, m.frame:GetFrameLevel() + 3
	local scale = size * k / NATIVE
	ns.Reparent(b, m.frame)
	ns.SetScale(b, scale)
	ns.ClearAllPoints(b)
	ns.SetPoint(b, "CENTER", m.frame, "BOTTOMLEFT", (x - m.rect[1]) * k / scale, (y - m.rect[2]) * k / scale)
	b:SetFrameLevel(level)
	b.cooldown:SetFrameLevel(level + 1)
	b.overlay:SetFrameLevel(level + 2)
	b.texts:SetFrameLevel(level + 5)
	b:Show()
	RefreshButton(b)
end

------------------------------------------------------------------------
-- Bars: buttons of R[key .. "_step"] (step, size) from the left of their
-- row, the frame art of the row over them
------------------------------------------------------------------------

-- Paging: an attribute driver writes the page into the bar1 frame, read by
-- its buttons through "useparent-actionpage" (the secure click, the drag
-- snippets and ActionOf compute the slot from it)
local function MainPageDriver()
	local d = ""
	local function Index(name)
		local fn = API(name)
		return fn and fn()
	end
	local vehicle = Index("GetVehicleBarIndex")
	local override = Index("GetOverrideBarIndex")
	local temp = Index("GetTempShapeshiftBarIndex")
	if vehicle then
		d = d .. format("[vehicleui] %d; [possessbar] %d; ", vehicle, vehicle)
	end
	if override then
		d = d .. format("[overridebar] %d; ", override)
	end
	if temp then
		d = d .. format("[shapeshift] %d; ", temp)
	end
	return d .. "[bar:2] 2; [bar:3] 3; [bar:4] 4; [bar:5] 5; [bar:6] 6; "
		.. "[bonusbar:1] 7; [bonusbar:2] 8; [bonusbar:3] 9; [bonusbar:4] 10; [bonusbar:5] 11; 1"
end

local function LayoutRow(m, buttons, row, step)
	for i, b in ipairs(buttons) do
		PlaceButton(b, m, row[1] + (i - 1) * step[1] + step[2] / 2, row[2] + step[2] / 2, step[2])
	end
end

-- first: the action before the first button (nil: paged); command: the
-- binding command of its keys
local function NewBar(key, label, order, first, command)
	ns.RegisterModule({
		key = key,
		label = label,
		order = order,
		level = 30,
		Create = function(m)
			m.buttons = {}
			for i = 1, 12 do
				local b = NewButton(format("WC3C_Bar%sButton%d", key:sub(4), i), m.frame, first and (first + i), command .. i)
				if not first then
					b:SetID(i)
				end
				m.buttons[i] = b
			end
			if not first then
				local f = m.frame
				f:SetAttribute("actionpage", 1)
				f:HookScript("OnAttributeChanged", function(_, name)
					if name == "actionpage" then
						for _, b in ipairs(m.buttons) do
							RefreshButton(b)
						end
					end
				end)
				RegisterAttributeDriver(f, "actionpage", MainPageDriver())
			end
		end,
		Layout = function(m)
			LayoutRow(m, m.buttons, m.rect, R[key .. "_step"])
			ns.Pieces(m, "front", { key .. "_over" }, m.frame, m.frame:GetFrameLevel() + 6)
		end,
	})
end

NewBar("bar1", "Action bar 1", 30, nil, "ACTIONBUTTON")
NewBar("bar2", "Action bar 2", 31, 60, "MULTIACTIONBAR1BUTTON")
NewBar("bar3", "Action bar 3", 32, 48, "MULTIACTIONBAR2BUTTON")

-- the extra rows over the chat
local EXTRA_ROWS = {
	{ first = 36, command = "MULTIACTIONBAR4BUTTON", name = "WC3C_Bar5Button" },
	{ first = 24, command = "MULTIACTIONBAR3BUTTON", name = "WC3C_Bar4Button" },
}

ns.RegisterModule({
	key = "extrabars",
	label = "Extra action bars",
	order = 46,
	level = 43,
	Create = function(m)
		m.rows = {}
		for r, row in ipairs(EXTRA_ROWS) do
			m.rows[r] = {}
			for i = 1, 12 do
				m.rows[r][i] = NewButton(row.name .. i, m.frame, row.first + i, row.command .. i)
			end
		end
	end,
	Layout = function(m)
		ns.Pieces(m, "front", { "extra_over" }, m.frame, m.frame:GetFrameLevel() + 6)
		for r, buttons in ipairs(m.rows) do
			LayoutRow(m, buttons, R["extra" .. r], R.extra_step)
		end
	end,
})

------------------------------------------------------------------------
-- Key bindings: the keys of Blizzard's bars click our buttons
------------------------------------------------------------------------

local bindOwner = CreateFrame("Frame", "WC3C_BindingOwner", UIParent)

local function UpdateBindings()
	if InCombatLockdown() then
		ns.RunOOC("bindings", UpdateBindings)
		return
	end
	ClearOverrideBindings(bindOwner)
	for _, b in ipairs(ns.buttons) do
		for _, key in ipairs({ GetBindingKey(b.commandName) }) do
			SetOverrideBindingClick(bindOwner, false, key, b:GetName(), "LeftButton")
		end
		UpdateHotkey(b)
	end
end

ns.On("WC3C_READY", function()
	HookQuickFrame()
	UpdateLock()
	UpdateBindings()
	pending = "full"
end)
ns.On("UPDATE_BINDINGS", function()
	if ns.initialized then
		UpdateBindings()
	end
end)
