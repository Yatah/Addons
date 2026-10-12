-- Target group above the right side of the central HUD. Art coordinates,
-- shared by both themes.
--
-- The group copies Blizzard's own target frame: the frame art (t_frame) is
-- the texture of TargetFrameTemplate (191.5 x 65 Blizzard units, centred in
-- its 232 x 100 frame) at 2 art px per unit, scaled by SCALE. Its target of
-- target, auras and cast bar go where Blizzard anchors them on that frame
-- (Blizzard_UnitFrame TargetFrame.xml / .lua, WoW Forever 1.60.1):
--   ToT       TOPRIGHT on the frame's BOTTOMRIGHT, +12, +10 (120 x 49)
--   auras     TOPLEFT on the texture's BOTTOMLEFT, +5, +9 (rows of 122)
--   cast bar  TOPLEFT on the frame's BOTTOMLEFT, +43, +5 (150 x 10), lower
--             with a ToT or under the aura rows (Blizzard moves it)
-- Blizzard's transparent target frame is laid on ns.TARGET_FRAME (Target.lua):
-- its auras and cast bar are shown there, at their original place and size.
local _, ns = ...
local R, F = ns.MOBA.r, ns.MOBA.front
local SCALE = .80
local U = 2 * SCALE -- art px per Blizzard unit
local function Move(keys, pieces, oldX, oldY, x, y, scale)
    for _, key in ipairs(keys) do
        local r = R[key]
        R[key] = { x + (r[1]-oldX)*scale, y + (r[2]-oldY)*scale, r[3]*scale, r[4]*scale }
    end
    for _, key in ipairs(pieces) do
        local p = F[key]
        p.texW, p.texH = p.w, p.h -- sampling rect stays unchanged in the atlas
        p.x, p.y = x + (p.x-oldX)*scale, y + (p.y-oldY)*scale
        p.w, p.h = p.w*scale, p.h*scale
    end
end
Move({"target","t_portrait","t_name","t_lvl","t_health","t_power"},
    {"t_frame"},2330,242,2045,575,SCALE)
-- (combo sockets under the portrait, as in the original art)
Move({"combo1","combo2","combo3","combo4","combo5"},
    {"sockets"},2330,242,2045,575,SCALE)

-- Blizzard's target frame around the texture: top left, bottom, right
local tex = F.t_frame
local texL, texB, texT = tex.x, tex.y, tex.y + tex.h
local frameL = texL - (232 - tex.texW / 2) / 2 * U
local frameT = texT + (100 - tex.texH / 2) / 2 * U
local frameB, frameR = frameT - 100 * U, frameL + 232 * U
ns.TARGET_FRAME = { x = frameL, y = frameT, unit = U }

-- target of target: Blizzard's 120 x 49 frame, top right at the frame's
-- bottom right + (12, 10), same scale as the target
Move({"tot","tot_portrait","tot_name","tot_health"},
    {"tot_frame"},2600,384,frameR + 12*U - 120*U,frameB + 10*U - 49*U,SCALE)

-- (our own auras / cast bar when Blizzard's cannot be shown: same place)
R.t_auras = {texL + 5*U, texB + 9*U - 48*U, 122*U, 48*U}
R.t_cast = {frameL + 43*U, frameB + 5*U - 30, 150*U, 30}

-- the target's pet (no Blizzard frame): under the cast bar's lowest place
Move({"tpet","tpet_portrait","tpet_name","tpet_health","tpet_power"},
    {"tpet_frame"},2453,118,2045,351.2,.60)
R.tpet_cast = {2045,413,144,12}
