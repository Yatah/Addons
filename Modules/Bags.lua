--[[
	WC3 Console - bags: Blizzard's bag bar upright in the thin column of the
	HUD (backpack on top, the 4 bags, the reagent bag, then the key ring's box
	lying, as Blizzard turns it in its vertical bag bar), centred in the
	evenly spaced cells of the art; the opened bags above the action bars.
]]

local _, ns = ...
local R = ns.R

-- cell i (R.bag1 .. bag7): its button. key: the key ring, shown by Blizzard
-- only when the game gives one (C_ActionBar.ShouldShowKeyring)
local BAGS = {
	{ "MainMenuBarBackpackButton" },
	{ "CharacterBag0Slot" },
	{ "CharacterBag1Slot" },
	{ "CharacterBag2Slot" },
	{ "CharacterBag3Slot" },
	{ "CharacterReagentBag0Slot" },
	{ "KeyRingButton", key = true },
}

-- The key ring's own box lying (45 x 33), as Blizzard turns it in its
-- vertical bag bar (its UpdateOrientation). A texture turns with its whole
-- rect: each picture of the box (frame, pushed, highlight, the key ring
-- itself) keeps an upright rect (33 x 45) centred on the button, a quarter
-- turn lays it exactly over the lying button. (Blizzard leaves its frame
-- textures at their top left corner: turned, they spill out of the button.)
-- The icon mask of the HUD follows the lying button (not the upright rect:
-- it would cut the picture). Again after each of Blizzard's updates of its
-- textures, and when its own bar stands it up again.
local KEY_TURN = math.pi / 2
local function FitKeyRing(b)
	local w, h = b:GetWidth(), b:GetHeight()
	if not (w and h and w > 0 and h > 0) then
		return
	end
	local pictures = { b.icon }
	for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture" }) do
		pictures[#pictures + 1] = b[get] and b[get](b)
	end
	for _, t in pairs(pictures) do
		if type(t) == "table" and t.SetRotation then
			t:ClearAllPoints()
			t:SetPoint("CENTER", b, "CENTER", 0, 0)
			t:SetSize(h, w)
			t:SetRotation(KEY_TURN)
		end
	end
	if b.wc3cMask then
		b.wc3cMask:ClearAllPoints()
		b.wc3cMask:SetAllPoints(b)
	end
end

local function LayKeyRing(b)
	local w, h = b:GetWidth(), b:GetHeight()
	if b.UpdateOrientation and (w or 0) < (h or 0) then
		b:UpdateOrientation(false)
	end
	FitKeyRing(b)
end

local placing = false
local function LayoutButtons(m)
	local k = ns.k
	for i, cell in ipairs(BAGS) do
		local b, c = _G[cell[1]], R["bag" .. i]
		if b and c then
			m.watchButton(b)
			if not b.wc3cNative then
				local w = b:GetWidth()
				b.wc3cNative = (w and w > 0) and w or 37
				ns.MaskIcon(b)
				if cell.key and type(b.UpdateTextures) == "function" then
					hooksecurefunc(b, "UpdateTextures", LayKeyRing)
				end
			end
			if cell.key then
				-- (its own bar, hidden, stands it up again on each of its
				-- layouts: laid down again then, from the size hooks)
				LayKeyRing(b)
			end
			-- as big as its cell allows, its proportions kept
			local width, height = b:GetWidth(), b:GetHeight()
			width = (width and width > 0) and width or b.wc3cNative
			height = (height and height > 0) and height or width
			local scale = math.min(c[3] / width, c[4] / height) * k
			-- centred in its cell
			local x, y = c[1] + c[3] / 2, c[2] + c[4] / 2
			if b:IsProtected() then
				-- (a protected button cannot hang on the module)
				ns.Reparent(b, UIParent)
				ns.SetScale(b, scale)
				ns.Follow(m, b, "CENTER", x, y)
			else
				ns.Reparent(b, m.frame)
				ns.SetScale(b, scale)
				ns.ClearAllPoints(b)
				ns.SetPoint(b, "CENTER", m.frame, "BOTTOMLEFT", (x - m.rect[1]) * k / scale, (y - m.rect[2]) * k / scale)
			end
			b:SetFrameLevel(m.frame:GetFrameLevel() + 4)
			if not cell.key then
				b:Show()
			end
		end
	end
end

local function PlaceButtons(m)
	if placing then
		return
	end
	if InCombatLockdown() then
		ns.RunOOC("bagbuttons", function() PlaceButtons(m) end)
		return
	end
	placing = true
	ns.Try("bag buttons", LayoutButtons, m)
	placing = false
end

local function Containers()
	local list = {}
	for i = 0, (_G.NUM_CONTAINER_FRAMES or 13) do
		local f = _G[i == 0 and "ContainerFrameCombinedBags" or ("ContainerFrame" .. i)]
		if f then
			list[#list + 1] = f
		end
	end
	return list
end

-- a frame covering the whole screen (UIParent, Blizzard's bags container)
local function FullScreen(f)
	if f == nil or f == UIParent then
		return true
	end
	local l, b, w, h = f:GetRect()
	if not l then
		return false
	end
	local k = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
	return math.abs(l * k) < 2 and math.abs(b * k) < 2 and math.abs(w * k - UIParent:GetWidth()) < 2 and math.abs(h * k - UIParent:GetHeight()) < 2
end

-- Opened bags: Blizzard stacks them in columns (the first bag of a column
-- anchored to the screen or to a container frame, the next ones to the bag
-- under them), where each character's Edit Mode layout says. The columns
-- are moved together: their bottom right corner at the bottom right of
-- R.bagsOpen, the same for every character.
local function AdjustContainers(m)
	if InCombatLockdown() then
		ns.RunOOC("bag-containers", function() AdjustContainers(m) end)
		return
	end
	if not m.db.moveBags then
		return
	end
	local frames, isBag = {}, {}
	for _, f in ipairs(Containers()) do
		isBag[f] = true
		if f:IsShown() then
			frames[#frames + 1] = f
		end
	end
	local sw, g, k = UIParent:GetWidth(), R.bagsOpen, ns.k
	local spotX, spotY = ns.ox + (g[1] + g[3]) * k - sw, ns.oy + g[2] * k
	-- the first bag of each column: its bottom right corner (from the
	-- bottom right of the screen, UIParent units)
	local roots, baseX, baseY, later = {}, nil, nil, false
	for _, f in ipairs(frames) do
		local point, rel, relPoint, x, y = f:GetPoint(1)
		if point and not isBag[rel] then
			local s = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
			if f:GetNumPoints() == 1 and point == "BOTTOMRIGHT" and relPoint == "BOTTOMRIGHT" and x and y and FullScreen(rel) then
				x, y = x * s, y * s
			else
				-- any other anchor: where the bag is on the screen
				local r, b = f:GetRight(), f:GetBottom()
				if r and b then
					x, y = r * s - sw, b * s
				else
					x, later = nil, true
				end
			end
			if x then
				roots[#roots + 1] = { f, x, y, s }
				if not baseX or x > baseX + 1 or (math.abs(x - baseX) <= 1 and y < baseY) then
					baseX, baseY = x, y
				end
			end
		end
	end
	for _, r in ipairs(roots) do
		local f, x, y, s = r[1], r[2], r[3], r[4]
		ns.ClearAllPoints(f)
		ns.SetPoint(f, "BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", (x - baseX + spotX) / s, (y - baseY + spotY) / s)
	end
	-- a bag not placed on the screen yet: again on the next frame
	if later and not m.bagsLater and (m.containerRetries or 0) < 2 then
		m.containerRetries = (m.containerRetries or 0) + 1
		m.bagsLater = true
		C_Timer.After(0, function()
			m.bagsLater = false
			AdjustContainers(m)
		end)
	end
end

ns.RegisterModule({
	key = "bags",
	label = "Bags",
	order = 40,
	level = 40,
	defaults = { moveBags = true },
	settings = {
		{ type = "toggle", key = "moveBags", label = "Open bags above the action bars" },
	},
	Create = function(m)
		ns.Reparent(_G.BagsBar, ns.hider)
		-- (Blizzard places the buttons again on bag / layout changes, also
		-- when a spell targets an item, e.g. Disenchant: put back after it)
		local function Buttons()
			if placing then
				return
			end
			ns.Defer("bag-layout", function()
				PlaceButtons(m)
			end, true)
		end
		local watched = {}
		m.watchButton = function(b)
			if watched[b] then return end
			watched[b] = true
			-- Observe Blizzard's completed operations, never replace its methods.
			for _, method in ipairs({ "SetPoint", "SetPointBase", "ClearAllPoints", "ClearAllPointsBase", "SetScale", "SetScaleBase", "SetParent", "SetSize", "SetWidth", "SetHeight" }) do
				if type(b[method]) == "function" then
					hooksecurefunc(b, method, Buttons)
				end
			end
		end
		if _G.BagsBar and type(_G.BagsBar.Layout) == "function" then
			hooksecurefunc(_G.BagsBar, "Layout", Buttons)
		end
		for _, e in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_ENTERING_WORLD", "EDIT_MODE_LAYOUTS_UPDATED", "PLAYER_REGEN_ENABLED", "DISPLAY_SIZE_CHANGED" }) do
			ns.On(e, Buttons)
		end
		if EventRegistry then
			EventRegistry:RegisterCallback("MainMenuBarManager.OnExpandChanged", Buttons, m)
			EventRegistry:RegisterCallback("ActionBarController.MainActionBarStateOverridden", Buttons, m)
		end
		local function Bags()
			m.containerRetries = 0
			ns.Defer("bag-containers", function()
				AdjustContainers(m)
			end, true)
		end
		if _G.UpdateContainerFrameAnchors then
			hooksecurefunc("UpdateContainerFrameAnchors", Bags)
		end
		-- (a bag Blizzard places without that function: once shown)
		for _, f in ipairs(Containers()) do
			f:HookScript("OnShow", Bags)
		end
	end,
	Layout = function(m)
		ns.Pieces(m, "front", { "bags_over" }, m.frame, m.frame:GetFrameLevel() + 6)
		PlaceButtons(m)
		m.containerRetries = 0
		AdjustContainers(m)
	end,
})
