--[[
	WC3 Console - Blizzard bars placed in the HUD: the micro menu (one row
	over the minimap) and the stance bar (above the minimap).
]]

local _, ns = ...
local min = math.min

------------------------------------------------------------------------
-- Micro menu: its buttons in one row filling the rect; Blizzard's own
-- layout is redone after each of its passes (out of combat: its scale and
-- points are protected in combat)
------------------------------------------------------------------------

local function MicroButtons(bar)
	local list = {}
	if type(_G.MICRO_BUTTONS) == "table" then
		for _, name in ipairs(_G.MICRO_BUTTONS) do
			local b = _G[name]
			if b and b:IsShown() then
				list[#list + 1] = b
			end
		end
	end
	if #list == 0 then
		for _, c in ipairs({ bar:GetChildren() }) do
			if c:IsShown() and c:GetObjectType() == "Button" then
				list[#list + 1] = c
			end
		end
		table.sort(list, function(a, b)
			return (a:GetLeft() or 0) < (b:GetLeft() or 0)
		end)
	end
	return list
end

local function LayoutMicro(m)
	local bar, r, k = m.bar, m.rect, ns.k
	local list = MicroButtons(_G.MicroMenu or bar)
	local n = #list
	local bw, bh = n > 0 and list[1]:GetWidth(), n > 0 and list[1]:GetHeight()
	if not (bw and bh and bw > 0 and bh > 0) then
		return
	end
	-- cell: the rect width over the buttons, as high as the rect at most
	local cw = min(r[3] / n, r[4] * bw / bh)
	local ch = cw * bh / bw
	local s = cw * k / bw
	ns.SetScale(bar, s)
	-- (the buttons may sit in a scaled frame inside the bar, MicroMenu in
	-- MicroMenuContainer: the bar takes that scale off, the buttons end up
	-- at s)
	local ok, f = pcall(function()
		return list[1]:GetEffectiveScale() / bar:GetEffectiveScale()
	end)
	if ok and ns.Num(f) and f > 0 and math.abs(f - 1) > 0.001 then
		ns.SetScale(bar, s / f)
	end
	local x0, y0 = (r[3] - cw * n) / 2, (r[4] - ch) / 2
	for i, b in ipairs(list) do
		ns.ClearAllPoints(b)
		ns.SetPoint(b, "TOPLEFT", m.frame, "TOPLEFT", (x0 + (i - 1) * cw) * k / s, -y0 * k / s)
	end
end

local function PlaceMicro(m)
	if m.busy then
		return
	end
	if InCombatLockdown() then
		ns.RunOOC("microrows", function()
			PlaceMicro(m)
		end)
		return
	end
	m.busy = true
	ns.Try("micro menu", LayoutMicro, m)
	m.busy = false
end

ns.RegisterModule({
	key = "micro",
	label = "Micro menu",
	order = 60,
	level = 62,
	insecure = true,
	Create = function(m)
		m.bar = _G.MicroMenuContainer or _G.MicroMenu
		if not m.bar then
			return
		end
		local function Again()
			if m.busy then return end
			ns.Defer("micro-layout", function()
				PlaceMicro(m)
			end, true)
		end
		ns.HookPosition(m.bar, function()
			PlaceMicro(m)
		end)
		if _G.MicroMenu and _G.MicroMenu.Layout then
			hooksecurefunc(_G.MicroMenu, "Layout", Again)
		end
		if _G.UpdateMicroButtons then
			hooksecurefunc("UpdateMicroButtons", Again)
		end
	end,
	Layout = function(m)
		local bar = m.bar
		if not bar then
			return
		end
		ns.Reparent(bar, m.frame)
		bar:SetFrameLevel(m.frame:GetFrameLevel() + 2)
		-- no background of its own: the buttons sit on the HUD
		for _, f in ipairs({ bar, _G.MicroMenu }) do
			for _, region in ipairs({ f:GetRegions() }) do
				region:SetAlpha(0)
			end
		end
		ns.ClearAllPoints(bar)
		ns.SetPoint(bar, "CENTER", m.frame, "CENTER", 0, 0)
		PlaceMicro(m)
	end,
})

------------------------------------------------------------------------
-- Stance bar: Blizzard's, at its own size, from the bottom left of its rect
------------------------------------------------------------------------

local function PlaceStance(m)
	local bar = m.bar
	if bar:IsProtected() and InCombatLockdown() then
		ns.RunOOC(bar, function()
			PlaceStance(m)
		end)
		return
	end
	if math.abs((bar:GetScale() or 1) - 1) > 0.01 then
		ns.SetScale(bar, 1)
	end
	ns.Follow(m, bar, "BOTTOMLEFT", m.rect[1], m.rect[2])
end

ns.RegisterModule({
	key = "stance",
	label = "Stance bar",
	order = 66,
	level = 64,
	Create = function(m)
		m.bar = _G.StanceBar or _G.StanceBarFrame or _G.ShapeshiftBarFrame
		if m.bar then
			ns.HookPosition(m.bar, function()
				PlaceStance(m)
			end)
		end
	end,
	Layout = function(m)
		if m.bar then
			PlaceStance(m)
		end
	end,
})
