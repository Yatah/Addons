-- Retail textures and controls only. No generated ledger artwork.
local _, ns = ...
local Eco = ns.Economy
local max, min, abs = math.max, math.min, math.abs
local T = { registry = {}, SKINS = {} }
Eco.Theme = T
local THEMES = {
	merchant = {
		label = "Merchant's Ledger",
		about = "Blizzard spellbook parchment, dark ink and green highlights.",
		light = true, decor = {},
		c = {
			ink = { 0.20, 0.13, 0.06 }, muted = { 0.26, 0.19, 0.12 }, title = { 0.33, 0.18, 0.05 }, note = { 0.07, 0.32, 0.17 },
			positive = { 0.03, 0.28, 0.08 }, negative = { 0.45, 0.05, 0.03 }, uncertain = { 0.30, 0.17, 0.02 },
			line = { 0.42, 0.29, 0.15, 0.55 }, rowAlt = { 0.42, 0.28, 0.12, 0.07 }, select = { 0.10, 0.40, 0.20, 0.20 },
			card = { 0.45, 0.30, 0.12, 0.08 }, cardEdge = { 0.45, 0.31, 0.16, 0.55 },
			cover = { 1, 0.86, 0.55 }, coverMuted = { 0.88, 0.78, 0.62 }, tab = { 0.95, 0.91, 0.78 },
			button = { 1, 0.90, 0.68 }, metal = { 0.80, 0.63, 0.30 }, scroll = { 0.55, 0.38, 0.18, 0.9 },
			bar = { 0.12, 0.42, 0.20 }, barBack = { 0.35, 0.23, 0.10, 0.22 }, chart = { 0.10, 0.30, 0.50 },
			stamp = { verified = { 0.05, 0.45, 0.15 }, review = { 0.30, 0.17, 0.02 }, sold = { 0.62, 0.12, 0.08 } },
		},
		states = { normal = 1, hover = 1.18, pressed = 0.8, disabled = 0.5 },
	},
	bilgewater = {
		label = "Bilgewater Treasury",
		about = "Blizzard auction panels, copper headings and goblin green highlights.",
		light = false, decor = { rivets = true },
		c = {
			ink = { 0.90, 0.88, 0.82 }, muted = { 0.62, 0.62, 0.58 }, title = { 0.95, 0.66, 0.38 }, note = { 0.45, 0.85, 0.52 },
			positive = { 0.40, 0.92, 0.45 }, negative = { 1, 0.42, 0.36 }, uncertain = { 1, 0.75, 0.25 },
			line = { 0.74, 0.44, 0.25, 0.45 }, rowAlt = { 1, 1, 1, 0.035 }, select = { 0.35, 0.85, 0.45, 0.16 },
			card = { 0, 0, 0, 0.28 }, cardEdge = { 0.74, 0.44, 0.25, 0.45 },
			cover = { 0.96, 0.70, 0.42 }, coverMuted = { 0.72, 0.70, 0.66 }, tab = { 1, 0.92, 0.80 },
			button = { 1, 0.86, 0.66 }, metal = { 0.74, 0.44, 0.25 }, scroll = { 0.74, 0.44, 0.25, 0.9 },
			bar = { 0.30, 0.80, 0.40 }, barBack = { 0, 0, 0, 0.4 }, chart = { 0.45, 0.85, 0.95 },
			stamp = { verified = { 0.40, 0.92, 0.45 }, review = { 1, 0.75, 0.25 }, sold = { 1, 0.45, 0.35 } },
		},
		states = { normal = 1, hover = 1.25, pressed = 0.8, disabled = 0.45 },
	},
	prince = {
		label = "Trade Prince's Ledger",
		about = "Blizzard spellbook parchment with jade tones and gold headings.",
		light = true, decor = { coins = true },
		c = {
			ink = { 0.14, 0.12, 0.08 }, muted = { 0.25, 0.20, 0.13 }, title = { 0.05, 0.27, 0.15 }, note = { 0.05, 0.30, 0.17 },
			positive = { 0.03, 0.28, 0.10 }, negative = { 0.45, 0.04, 0.06 }, uncertain = { 0.30, 0.17, 0.02 },
			line = { 0.66, 0.52, 0.20, 0.6 }, rowAlt = { 0.55, 0.45, 0.20, 0.07 }, select = { 0.08, 0.36, 0.20, 0.18 },
			card = { 0.55, 0.45, 0.20, 0.07 }, cardEdge = { 0.70, 0.56, 0.24, 0.6 },
			cover = { 1, 0.86, 0.45 }, coverMuted = { 0.84, 0.82, 0.66 }, tab = { 1, 0.93, 0.74 },
			button = { 1, 0.88, 0.55 }, metal = { 0.88, 0.71, 0.32 }, scroll = { 0.70, 0.56, 0.24, 0.9 },
			bar = { 0.06, 0.40, 0.22 }, barBack = { 0.55, 0.45, 0.20, 0.2 }, chart = { 0.06, 0.32, 0.48 },
			stamp = { verified = { 0.04, 0.42, 0.18 }, review = { 0.30, 0.17, 0.02 }, sold = { 0.62, 0.10, 0.12 } },
		},
		states = { normal = 1, hover = 1.15, pressed = 0.82, disabled = 0.5 },
	},
}
T.THEMES = THEMES
T.ORDER = { "merchant", "bilgewater", "prince" }

for key, th in pairs(THEMES) do th.key = key end
local current = THEMES.merchant
local STANDARD = _G.STANDARD_TEXT_FONT or [[Fonts\FRIZQT__.TTF]]
T.FONTS = {
    title = { STANDARD, 20 }, bookTitle = { STANDARD, 22 }, heading = { STANDARD, 14 },
    body = { STANDARD, 13 }, small = { STANDARD, 12 }, big = { STANDARD, 23 }, tab = { STANDARD, 14 },
}
local S = T.SKINS
function T.Current() return current end
function T.Color(name)
    local c = current.c[name] or current.c.ink
    return c[1],c[2],c[3],c[4] or 1
end
function T.Ink(r,g,b)
    if not current.light then return r,g,b end
    local mx,mn=max(r,g,b),min(r,g,b)
    if mx-mn < 0.15 then return T.Color(mx>0.75 and "ink" or "muted") end
    local k=0.42/max(mx,0.01)
    return r*k,g*k,b*k
end

-- Inline profit colours must follow the parchment palette too.
function T.ReadableText(text)
    if not current.light or type(text)~="string" then return text end
    return (text:gsub("|c(%x%x)(%x%x)(%x%x)(%x%x)",function(alpha,r,g,b)
        local red,green,blue=T.Ink(tonumber(r,16)/255,tonumber(g,16)/255,tonumber(b,16)/255)
        return string.format("|c%s%02x%02x%02x",alpha,math.floor(red*255+0.5),math.floor(green*255+0.5),math.floor(blue*255+0.5))
    end))
end

-- Retail atlas names checked against Blizzard's SpellBookFrame XML.
-- Client lookup is authoritative; older clients use original Blizzard files.
T.assets = {}
function T.Asset(tex, atlas, fallback, coords)
    tex:SetTexCoord(0,1,0,1)
    tex:SetVertexColor(1,1,1,1)
    if atlas and C_Texture and C_Texture.GetAtlasInfo and tex.SetAtlas then
        local ok,info=pcall(C_Texture.GetAtlasInfo,atlas)
        if ok and info then
            local applied=pcall(tex.SetAtlas,tex,atlas,false)
            if applied then T.assets[atlas]="atlas"; return true end
        end
    end
    local ok=tex:SetTexture(fallback)
    if coords then tex:SetTexCoord(unpack(coords)) end
    T.assets[atlas or fallback]=ok==false and "missing" or "file fallback (verify in game)"
    return ok~=false
end
function T.Border(f, layout)
    if f.wc3cRetailBorder then return end
    local edge=CreateFrame("Frame",nil,f,"BackdropTemplate")
    edge:SetAllPoints(f)
    edge:EnableMouse(false)
    local applied=false
    if NineSliceUtil and NineSliceUtil.ApplyLayoutByName then
        applied=pcall(NineSliceUtil.ApplyLayoutByName,edge,layout or "InsetFrameTemplate")
    end
    if not applied and edge.SetBackdrop then
        edge:SetBackdrop({edgeFile=[[Interface\Tooltips\UI-Tooltip-Border]],edgeSize=14,
            insets={left=3,right=3,top=3,bottom=3}})
        edge:SetBackdropBorderColor(0.65,0.57,0.40,1)
    end
    f.wc3cRetailBorder=edge
end
function S.cover(f,th)
    if not f.wc3cCover then
        local bg=f:CreateTexture(nil,"BACKGROUND",nil,-8); bg:SetAllPoints()
        f.wc3cCover={bg=bg}
        -- Native Blizzard metal edging, without a reserved title strip.
        local edge=CreateFrame("Frame",nil,f,"BackdropTemplate")
        edge:SetAllPoints(f)
        edge:EnableMouse(false)
        edge:SetBackdrop({edgeFile=[[Interface\DialogFrame\UI-DialogBox-Border]],edgeSize=24,
            insets={left=6,right=6,top=6,bottom=6}})
        edge:SetBackdropBorderColor(0.88,0.62,0.32,1)
        f.wc3cRetailBorder=edge
    end
    T.Asset(f.wc3cCover.bg,nil,[[Interface\FrameGeneral\UI-Background-Rock]])
    local v=th.key=="prince" and {0.48,0.63,0.48} or th.key=="bilgewater" and {0.68,0.53,0.41} or {0.65,0.60,0.48}
    f.wc3cCover.bg:SetVertexColor(v[1],v[2],v[3])
end
function S.page(f,th,side)
    if not f.wc3cPage then
        local bg=f:CreateTexture(nil,"BACKGROUND",nil,-6); bg:SetAllPoints()
        f.wc3cPage={bg=bg}
    end
    local tex=f.wc3cPage.bg
    if th.light then
        T.Asset(tex,"spellbook-background-evergreen-"..side,
            ns.ART..[[retail\Spellbook-Page-1]],
            side=="left" and {0.17,0.56,0.07,0.91} or {0.56,0.95,0.07,0.91})
        if th.key=="prince" then tex:SetVertexColor(0.91,0.98,0.90) end
    else
        T.Asset(tex,"auctionhouse-background-sell-right",ns.ART..[[retail\AuctionHouseBackgrounds]],
            {2/2048,366/2048,2/1024,396/1024})
    end
end
function S.spine(tex) tex:SetColorTexture(0,0,0,0) end
local colours={title="title",heading="title",body="ink",small="ink",muted="muted",note="note",big="ink",
    cover="cover",coverMuted="coverMuted",bookTitle="cover",tab="tab",button="button",
    positive="positive",negative="negative",uncertain="uncertain"}
local fonts={muted="small",note="small",cover="body",coverMuted="small",button="body",
    positive="body",negative="body",uncertain="body"}
local dark={cover=true,coverMuted=true,bookTitle=true,tab=true,button=true}
function S.text(fs,th,kind)
    local font=T.FONTS[fonts[kind] or kind] or T.FONTS.body
    fs:SetFont(font[1],font[2],"")
    if not fs.wc3cColored then fs:SetTextColor(T.Color(colours[kind] or "ink")) end
    fs:SetShadowColor(0,0,0,0.8)
    fs:SetShadowOffset((dark[kind] or not th.light) and 1 or 0,(dark[kind] or not th.light) and -1 or 0)
end
function S.line(tex,th,name) tex:SetColorTexture(T.Color(name or "line")) end
function S.tint(tex,th,name) tex:SetVertexColor(T.Color(name or "metal")) end
function S.card(f,th)
    if not f.wc3cCard then
        local bg=f:CreateTexture(nil,"BACKGROUND",nil,1); bg:SetAllPoints()
        f.wc3cCard={bg=bg}
        T.Border(f,"InsetFrameTemplate")
    end
    local bg=f.wc3cCard.bg
    if th.light then bg:SetColorTexture(0.96,0.87,0.65,0.40)
    else
        T.Asset(bg,"auctionhouse-background-sell-right",ns.ART..[[retail\AuctionHouseBackgrounds]],
            {2/2048,366/2048,2/1024,396/1024})
    end
end
function S.settingsPanel(f,th)
    if not f.settingsBackground then
        f.settingsBackground=f:CreateTexture(nil,"BACKGROUND");f.settingsBackground:SetAllPoints()
        T.Border(f,"InsetFrameTemplate")
    end
    if th.light then f.settingsBackground:SetColorTexture(0.84,0.75,0.56,1)
    else f.settingsBackground:SetColorTexture(0.07,0.07,0.06,1) end
end
function S.button(b) T.ButtonState(b) end
function T.ButtonState(b)
    local fs=b:GetFontString()
    if fs then
        if not b:IsEnabled() then fs:SetTextColor(0.5,0.5,0.5)
        elseif b.wc3cOn then fs:SetTextColor(1,1,1)
        else fs:SetTextColor(1,0.82,0.4) end
    end
    if b.wc3cSelected then b.wc3cSelected:SetShown(b.wc3cOn==true) end
end
function S.tab(b) T.TabState(b) end
function T.TabState(b)
    b.wc3cOn=b.wc3cOn==true
    T.ButtonState(b)
end
function S.bar(f)
    f.wc3cBack:SetColorTexture(0,0,0,0.45)
    T.Asset(f.wc3cFill,nil,[[Interface\TargetingFrame\UI-StatusBar]])
    f.wc3cFill:SetVertexColor(T.Color("bar"))
end
function S.stamp(f,th,kind)
    local labels={verified="Verified",review="Needs review",sold="Sold"}
    local icons={verified="ReadyCheck-Ready",review="ReadyCheck-Waiting",sold="ReadyCheck-Ready"}
    f.icon:SetTexture([[Interface\RaidFrame\]]..(icons[kind] or icons.review))
    f.label:SetText(labels[kind] or labels.review)
    local c=th.c.stamp[kind] or th.c.stamp.review
    f.label:SetTextColor(c[1],c[2],c[3])
end
function S.check(c)
    if c.label then c.label:SetTextColor(T.Color("ink")); c.label:SetShadowOffset(0,0) end
end
function S.list(list,th) if list.Skin then list:Skin(th) end end
function S.coin(tex) tex:SetTexture([[Interface\Icons\INV_Misc_Coin_02]]); tex:Show() end
function T.Skin(obj,role,a,b)
    T.registry[#T.registry+1]={obj,role,a,b}; S[role](obj,current,a,b); return obj
end
function T.Set(key)
    current=THEMES[key] or THEMES.merchant
    for _,r in ipairs(T.registry) do S[r[2]](r[1],current,r[3],r[4]) end
    return current.key
end
function T.Load() local st=Eco.DB().settings; st.theme=T.Set(st.theme); return st.theme end
function T.Report()
    ns.Print("Retail ledger: "..current.label)
    for asset,status in pairs(T.assets) do ns.Print(asset..": "..status) end
end
