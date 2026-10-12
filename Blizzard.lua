--[[
	WC3 Console - Blizzard frames replaced by the enabled modules (a
	disabled module leaves its Blizzard frame alone).
	Rules learnt the hard way on this client:
	  - never pick up / place items or actions from addon code (taints item use)
	  - never replace methods of Blizzard templates
	  - frames whose code calls their parent keep their parent (made invisible)
	  - Blizzard's own action buttons are left alone: ours are secure action
	    buttons with their own display, never in Blizzard's action button
	    lists (see ActionBars), so Blizzard's code runs untainted and handles
	    its secret cooldowns itself
]]

local _, ns = ...

local function HideTrackingBars()
	for _, name in ipairs({ "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer", "StatusTrackingBarManager" }) do
		local f = _G[name]
		if f then
			f:SetAlpha(0)
			f:EnableMouse(false)
			for _, child in ipairs({ f:GetChildren() }) do
				child:EnableMouse(false)
			end
		end
	end
end

-- The frame of the class resources under the player frame (combo points,
-- totems...): PlayerBottomManagedFrameContainer on Forever, the older name
-- on older clients
function ns.PlayerResourceContainer()
	local get = _G.GetPlayerBottomManagedFrameContainer
	return (get and get()) or _G.PlayerBottomManagedFrameContainer or _G.PlayerFrameBottomManagedFramesContainer
end

local function HidePlayerFrame(m)
	local pf = _G.PlayerFrame
	if not pf then
		return
	end
	-- Keep what hangs on the player frame (pet frame, class resources,
	-- totems). On Forever the totems and the pet frame are put back in the
	-- container each time they are shown (ManagedFrameMixin:OnShow): the
	-- container itself leaves the player frame. (They are moved out too while
	-- hidden: under the hidden player frame their OnShow would never run.)
	local container = ns.PlayerResourceContainer()
	for _, f in ipairs({ _G.PetFrame, container, _G.TotemFrame }) do
		if f and f:GetParent() == pf then
			ns.Reparent(f, UIParent)
		end
	end
	ns.Reparent(pf, ns.hider)
	if container then
		local function Refit()
			C_Timer.After(0, function()
				ns.RunOOC("resources", function()
					ns.PlacePlayerResources(m)
				end)
			end)
		end
		container:HookScript("OnSizeChanged", Refit)
		container:HookScript("OnShow", Refit)
		container:HookScript("OnHide", Refit)
		ns.HookPosition(container, function()
			ns.PlacePlayerResources(m)
		end)
	end
	ns.HookPosition(_G.PetFrame, function()
		ns.UpdateFollowers(m)
	end)
end

-- Blizzard's button to leave a vehicle, or to ask a taxi to land early: a
-- child of the main action bar (hidden), moved to the free left corner of
-- the action panel (art px). Blizzard's own code shows it (when the player
-- can leave) and runs its click; moved out of combat when the game
-- protects it.
local LEAVE = { 1449, 208, 42, 42 }

local function KeepVehicleLeaveButton(m)
	local b = _G.MainMenuBarVehicleLeaveButton
	if not b then
		return
	end
	local function Place()
		if b:IsProtected() and InCombatLockdown() then
			ns.RunOOC("vehicleleave", Place)
			return
		end
		local w = b:GetWidth()
		ns.Reparent(b, UIParent)
		ns.SetScale(b, LEAVE[3] * ns.k / ((w and w > 0) and w or 32))
		ns.Follow(m, b, "CENTER", LEAVE[1] + LEAVE[3] / 2, LEAVE[2] + LEAVE[4] / 2)
	end
	Place()
	ns.HookPosition(b, Place)
	ns.On("WC3C_LAYOUT", Place) -- (the HUD scale changed)
end

local function DisableCastBar(cb)
	if not cb then
		return
	end
	cb:UnregisterAllEvents()
	cb:HookScript("OnShow", cb.Hide)
	cb:Hide()
end

-- The target frame stays shown (its aura code runs only while it is
-- visible: its auras are shown by the target panel), fully transparent and
-- without mouse, as its target of target
local function HideTargetFrame()
	local tf = _G.TargetFrame
	if not tf then
		return
	end
	ns.Reparent(tf, UIParent)
	for _, f in ipairs({ tf, _G.TargetFrameToT or tf.totFrame }) do
		f:SetAlpha(0)
		f:EnableMouse(false)
		-- (range / fading code sets its alpha again; in combat that alpha can
		-- be a secret value: not compared)
		hooksecurefunc(f, "SetAlpha", function(self, a)
			if ns.IsSecret(a) or a ~= 0 then
				self:SetAlpha(0)
			end
		end)
	end
end

function ns.SetupBlizzard()
	local bar1 = ns.Enabled("bar1")
	if bar1 then
		ns.Reparent(_G.MainActionBar or _G.MainMenuBar, ns.hider)
		ns.Try("vehicle leave button", KeepVehicleLeaveButton, bar1)
	end
	if ns.Enabled("bar2") then
		ns.Reparent(_G.MultiBarBottomLeft, ns.hider)
	end
	if ns.Enabled("bar3") then
		ns.Reparent(_G.MultiBarBottomRight, ns.hider)
	end
	if ns.Enabled("extrabars") then
		ns.Reparent(_G.MultiBarRight, ns.hider)
		ns.Reparent(_G.MultiBarLeft, ns.hider)
	end
	local player = ns.Enabled("player")
	if player then
		HideTrackingBars()
		ns.Try("player frame", HidePlayerFrame, player)
		DisableCastBar(_G.PlayerCastingBarFrame or _G.CastingBarFrame)
		DisableCastBar(_G.OverlayPlayerCastingBarFrame)
	end
	if ns.Enabled("pet") then
		-- (the pet panel has its own cast bar)
		DisableCastBar(_G.PetCastingBarFrame)
	end
	if ns.Enabled("target") then
		-- (its cast bar and combo points stay inside it, transparent)
		ns.Try("target frame", HideTargetFrame)
	elseif ns.Enabled("targettarget") and _G.TargetFrameToT then
		_G.TargetFrameToT:SetAlpha(0)
	end
end
