-- Information preserved when WC3Console replaces Blizzard unit frames.
local _, ns = ...
local function Truth(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok and not ns.IsSecret(value) then return value end
end

local function RaidMark(m)
    local icon = m.wc3RaidMark
    if not icon then return end
    local index = Truth(_G.GetRaidTargetIndex, m.unit)
    if type(index) == "number" and index >= 1 and index <= 8 then
        if SetRaidTargetIconTexture then
            SetRaidTargetIconTexture(icon, index)
        else
            local x, y = (index - 1) % 4, math.floor((index - 1) / 4)
            icon:SetTexCoord(x / 4, (x + 1) / 4, y / 2, (y + 1) / 2)
        end
        icon:Show()
    else icon:Hide() end
end

local function PvP(m)
    local f = m.wc3PvP
    if not f then return end
    local ffa = Truth(_G.UnitIsPVPFreeForAll, "player")
    local flagged = ffa or Truth(_G.UnitIsPVP, "player")
    local faction = Truth(_G.UnitFactionGroup, "player")
    f:SetShown(flagged == true)
    if not flagged then return end
    local atlas = ffa and "UI-HUD-UnitFrame-Player-PVP-FFAIcon"
        or (faction == "Horde" and "UI-HUD-UnitFrame-SmallCircle-Horde")
        or "UI-HUD-UnitFrame-SmallCircle-Alliance"
    if ns.HasAtlas(atlas) then f.icon:SetAtlas(atlas)
    else f.icon:SetTexture("Interface\\TargetingFrame\\UI-PVP-" .. (ffa and "FFA" or faction or "Alliance")) end
    local running = Truth(_G.IsPVPTimerRunning)
    local ms = running and Truth(_G.GetPVPTimer)
    if ns.Num(ms) and ms > 0 and not ffa then
        local seconds = math.ceil(ms / 1000)
        f.timer:SetFormattedText("%d:%02d", math.floor(seconds / 60), seconds % 60)
    else f.timer:SetText("") end
end

local function Layout()
    local player, target, pet = ns.Enabled("player"), ns.Enabled("target"), ns.Enabled("pet")
    if player and player.wc3PvP then
        local r = ns.R.p_model
        ns.Place(player.wc3PvP, player, r[1] - 25, r[2] + r[4] - 28, 24, 24)
    end
    if target and target.wc3RaidMark then
        local r = ns.R.t_portrait
        ns.Place(target.wc3RaidMark, target, r[1] + r[3] / 2, r[2] + r[4] + 4, 28, 28, "CENTER")
    end
    if pet and pet.wc3Happiness then
        local r = ns.R.pet_portrait
        ns.Reparent(pet.wc3Happiness, pet.frame)
        pet.wc3Happiness:SetFrameLevel(pet.frame:GetFrameLevel() + 15)
        ns.Place(pet.wc3Happiness, pet, r[1] - 24, r[2] + 20, 22, 22)
        if pet.wc3Happiness.UpdateHappiness then pet.wc3Happiness:UpdateHappiness() end
    end
end

ns.On("WC3C_READY", function()
    local player, target, pet = ns.Enabled("player"), ns.Enabled("target"), ns.Enabled("pet")
    if player then
        local f = CreateFrame("Frame", nil, player.frame)
        f:SetFrameLevel(player.frame:GetFrameLevel() + 15)
        f.icon = f:CreateTexture(nil, "OVERLAY"); f.icon:SetAllPoints()
        f.timer = ns.NewFont(f, 13)
        f.timer:SetPoint("TOP", f, "BOTTOM", 0, -2)
        f:EnableMouse(true)
        f:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("PvP enabled", 1, 0.82, 0)
            GameTooltip:AddLine(Truth(_G.UnitIsPVPFreeForAll, "player") and "Free for all" or "Your character is flagged for PvP.", 1, 1, 1)
            GameTooltip:Show()
        end)
        f:SetScript("OnLeave", GameTooltip_Hide)
        player.wc3PvP = f
        local elapsed = 0
        -- Parent remains visible even when the PvP icon is hidden.
        player.frame:HookScript("OnUpdate", function(_, dt)
            elapsed = elapsed + dt
            if elapsed >= 1 then elapsed = 0; PvP(player) end
        end)
        ns.OnUnit("UNIT_FACTION", "player", function() PvP(player) end)
        ns.On("PLAYER_FLAGS_CHANGED", function() PvP(player) end)
        PvP(player)
    end
    if target then
        local holder = CreateFrame("Frame", nil, target.dyn)
        holder:SetAllPoints(target.frame)
        holder:SetFrameLevel(target.frame:GetFrameLevel() + 16)
        target.wc3RaidMark = holder:CreateTexture(nil, "OVERLAY")
        target.wc3RaidMark:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        local function Update() RaidMark(target) end
        ns.On("RAID_TARGET_UPDATE", Update)
        ns.On("PLAYER_TARGET_CHANGED", Update)
        ns.On("PLAYER_ENTERING_WORLD", Update)
        Update()
    end
    if pet and _G.PetFrameHappiness and _G.PetFrameHappiness.UpdateHappiness then
        -- Keep Blizzard's events, diet/loyalty tooltip and Forever artwork.
        pet.wc3Happiness = _G.PetFrameHappiness
    end
    for _, key in ipairs({ "player", "target", "pet", "targetpet" }) do
        local m = ns.Enabled(key)
        if m then
            local function UpdateState() ns.UpdateUnitHealth(m) end
            ns.OnUnit("UNIT_CONNECTION", m.unit, UpdateState)
            ns.OnUnit("UNIT_FLAGS", m.unit, UpdateState)
        end
    end
    Layout()
end)
ns.On("WC3C_LAYOUT", function() ns.RunOOC("hud-indicators", Layout) end)
