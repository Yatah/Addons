--[[
	WC3 Console - economy: The Goblin Ledger, the window of the economy. A
	book open on two pages, four bookmarks on its right edge (Overview, Make
	Gold, My Business, Market), its header (the market: realm and side, whose
	fortune, the last scan), its settings. Each page is a module of its own
	(Ledger*.lua): it shows the figures of the model (Fortune.lua,
	Opportunities.lua, Analysis.lua...), never computes them.
	The book keeps the state of each page (view, selection, filters,
	scrolling): a change of theme, of scale or a reopening finds it as it
	was. Nothing here is protected: the book can open, move and change in
	combat. Esc closes it; out of combat, Tab / Shift-Tab go from bookmark to
	bookmark, Up / Down move in the list, Right opens, Left goes back.
]]

local _, ns = ...
local Eco = ns.Economy
local floor, max, min, format = math.floor, math.max, math.min, string.format
local ipairs, pairs, type, tostring = ipairs, pairs, type, tostring

local T = Eco.Theme
local DB = Eco.DB

local B = { pages = {}, order = {}, state = {} }
Eco.Book = B

local DEFAULT_W, DEFAULT_H, MIN_W, MIN_H = 1180, 760, 1080, 720
local HEADER, FOOTER, BORDER, TABS_W, SPINE_W, PAD = 108, 28, 12, 12, 24, 30
B.PAD = PAD

------------------------------------------------------------------------
-- Parts of the book, dressed by the theme
------------------------------------------------------------------------

-- a text: kind = title, heading, body, small, muted, note, big, cover,
-- coverMuted, positive, negative, uncertain
function B.Text(parent, kind, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetJustifyH(justify or "LEFT")
	fs:SetWordWrap(false)
	T.Skin(fs, "text", kind or "body")
	return fs
end

-- a region across its parent at a height: its top left and its top right
-- at the same y (a RIGHT point would also set its vertical centre)
function B.Span(region, parent, y, left, right)
	region:ClearAllPoints()
	region:SetPoint("TOPLEFT", parent, "TOPLEFT", left or 0, y)
	region:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(right or 0), y)
	return region
end

-- a text coloured by meaning (the theme's colour, a word or a sign always
-- with it: the colour is never alone)
function B.Paint(fs, colour)
	fs:SetTextColor(T.Color(colour))
end

-- a tooltip on any frame: a title and a text
function B.Tip(frame, title, text)
    if not frame.HookScript then
        local hit=CreateFrame("Frame",nil,frame:GetParent())
        hit:SetAllPoints(frame); hit:EnableMouse(true)
        frame=hit
    end
	frame:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(title, 1, 0.82, 0)
		if text then
			GameTooltip:AddLine(type(text) == "function" and text() or text, 1, 1, 1, true)
		end
		GameTooltip:Show()
	end)
	frame:HookScript("OnLeave", function()
		GameTooltip:Hide()
	end)
end

-- a button of the book: a plate of the theme (3 slices), hover / pressed /
-- disabled states, its text never cut (it grows when it must)
function B.Button(parent, text, w, onClick, h)
    local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate")
    b:SetSize(w or 110,h or 28)
    b:SetText(text or "")
    local fs=b:GetFontString()
    fs:ClearAllPoints(); fs:SetPoint("LEFT",b,"LEFT",10,0); fs:SetPoint("RIGHT",b,"RIGHT",-10,0)
    fs:SetWordWrap(false); fs:SetJustifyH("CENTER")
    fs:SetFont(_G.STANDARD_TEXT_FONT or [[Fonts\FRIZQT__.TTF]],13,"")
    b.wc3cSelected=b:CreateTexture(nil,"OVERLAY")
    b.wc3cSelected:SetTexture([[Interface\QuestFrame\UI-QuestTitleHighlight]])
    b.wc3cSelected:SetBlendMode("ADD")
    b.wc3cSelected:SetAllPoints(); b.wc3cSelected:SetAlpha(0.25); b.wc3cSelected:Hide()
    b:HookScript("OnEnable",T.ButtonState); b:HookScript("OnDisable",T.ButtonState)
    if onClick then b:SetScript("OnClick",onClick) end
    T.Skin(b,"button")
    b.Fit=function(self,minW) self:SetWidth(max(minW or 0,(fs:GetStringWidth() or 0)+28)) end
    return b
end

-- Page controls retain their parent (and its visibility), but sit outside
-- the paper in a wrapping toolbar on the cover.
function B.QueueDock()
    if B.dockPending or not B.frame then return end
    B.dockPending=true
    C_Timer.After(0,function()
        B.dockPending=false
        if B.frame and B.frame:IsShown() then B.LayoutDock() end
    end)
end
function B.DockControl(control, caption, label)
    local page=B.buildingPage
    if not page then return control end
    page.dockControls=page.dockControls or {}
    for _,entry in ipairs(page.dockControls) do if entry.control==control then return control end end
    page.dockControls[#page.dockControls+1]={control=control,width=control:GetWidth(),caption=caption,label=label}
    control:HookScript("OnShow",B.QueueDock)
    control:HookScript("OnHide",B.QueueDock)
    return control
end
local dockButton=B.Button
function B.Button(...)
    return B.DockControl(dockButton(...))
end
function B.LayoutDock()
    local f=B.frame
    if not f or not f.toolbar then return end
    local page=B.pages[B.state.page]
    local x,y,rows=0,0,0
    local width=max(100,f:GetWidth()-44)
    for _,other in ipairs(B.order) do
        for _,entry in ipairs(other.dockControls or {}) do
            if entry.captionText then entry.captionText:Hide() end
        end
    end
    if page and not B.state.settings then
        for _,entry in ipairs(page.dockControls or {}) do
            local control=entry.control
            if control:IsVisible() then
                local caption=entry.caption
                local label=entry.label
                if caption and not entry.captionText then
                    entry.captionText=B.Text(f.toolbar,"coverMuted")
                    entry.captionText:SetText(caption)
                end
                local prefix=caption and (entry.captionText:GetStringWidth()+10) or 0
                local w=min(entry.width or 120,width-prefix)
                local checkLabel=control.label
                local suffix=checkLabel and (checkLabel:GetStringWidth()+8) or 0
                local span=w+prefix+suffix
                if x>0 and x+span>width then x=0;y=y-36 end
                control:ClearAllPoints()
                control:SetPoint("LEFT",f.toolbar,"TOPLEFT",x+prefix,y-16)
                control:SetWidth(w)
                if entry.captionText then
                    entry.captionText:ClearAllPoints();entry.captionText:SetPoint("LEFT",f.toolbar,"TOPLEFT",x,y-16);entry.captionText:Show()
                end
                if label then label:Hide() end
                if checkLabel then checkLabel:SetTextColor(T.Color("cover")) end
                x=x+span+12;rows=max(rows,1+floor(-y/36))
            end
        end
    end
    local height=rows>0 and rows*36+4 or 0
    f.toolbar:SetHeight(max(1,height));f.toolbar:SetShown(height>0)
    if f.dockHeight~=height then
        f.dockHeight=height
        f.book:ClearAllPoints();f.book:SetPoint("TOPLEFT",BORDER,-HEADER-height)
        f.book:SetPoint("BOTTOMRIGHT",-BORDER,FOOTER)
    end
end

-- a selected state for a button (a choice among several)
function B.SetOn(b, on)
	b.wc3cOn = on and true or false
	T.ButtonState(b)
end

-- a panel on a page
function B.Card(parent)
	local f = CreateFrame("Frame", nil, parent)
	T.Skin(f, "card")
	return f
end

-- a line
function B.Line(parent, layer)
	local t = parent:CreateTexture(nil, layer or "ARTWORK")
	T.Skin(t, "line")
	return t
end

-- a flourish under a title
function B.Flourish(parent)
	local t = parent:CreateTexture(nil, "ARTWORK")
	t:SetTexture([[Interface\QuestFrame\UI-QuestTitleHighlight]])
	t:SetSize(200, 3)
	T.Skin(t, "tint", "metal")
	return t
end

-- a progress bar: SetValue(0..1)
function B.Bar(parent)
	local f = CreateFrame("Frame", nil, parent)
	f.wc3cBack = f:CreateTexture(nil, "BACKGROUND")
	f.wc3cBack:SetAllPoints()
	f.wc3cFill = f:CreateTexture(nil, "ARTWORK")
	f.wc3cFill:SetPoint("TOPLEFT")
	f.wc3cFill:SetPoint("BOTTOMLEFT")
	f.wc3cFill:SetWidth(1)
	f.SetValue = function(self, v)
		v = max(0, min(1, v or 0))
		self.value = v
		self.wc3cFill:SetWidth(max(0.01, (self:GetWidth() or 0) * v))
		self.wc3cFill:SetShown(v > 0)
	end
	f:SetScript("OnSizeChanged", function(self)
		self:SetValue(self.value)
	end)
	T.Skin(f, "bar")
	return f
end

-- a stamp: "verified", "review", "sold"
function B.Stamp(parent,kind)
    local f=CreateFrame("Frame",nil,parent)
    f:SetSize(126,24)
    f.icon=f:CreateTexture(nil,"ARTWORK"); f.icon:SetSize(18,18); f.icon:SetPoint("LEFT")
    f.label=B.Text(f,"small"); f.label:SetPoint("LEFT",f.icon,"RIGHT",5,0); f.label:SetPoint("RIGHT")
    T.Skin(f,"stamp",kind)
    f.SetKind=function(self,k)
        for _,r in ipairs(T.registry) do if r[1]==self then r[3]=k; break end end
        T.SKINS.stamp(self,T.Current(),k)
    end
    return f
end

-- a check box with its label
function B.Check(parent, label, get, set)
	local c = ns.W.Check(parent, label, get, set)
	T.Skin(c, "check")
	return B.DockControl(c)
end

-- a number box (the gold, percents): Eco.NumberBox
function B.Number(parent, w, get, set)
	return B.DockControl(Eco.NumberBox(parent, w, get, set))
end

-- a text box
function B.Input(parent, w, onChange)
	local ok, e = pcall(CreateFrame, "EditBox", nil, parent, "InputBoxTemplate")
	if not ok or not e then
		e = CreateFrame("EditBox", nil, parent)
		local bg = e:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0, 0, 0, 0.5)
		e:SetFontObject("GameFontHighlightSmall")
	end
	e:SetSize(w, 20)
	e:SetAutoFocus(false)
	e:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	e:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
	end)
	if onChange then
		e:SetScript("OnTextChanged", function(self, user)
			if user then
				onChange(self:GetText())
			end
		end)
	end
	return B.DockControl(e)
end

-- a dropdown of the book: a button of the theme opening the choices
function B.Dropdown(parent, w)
	local b = B.Button(parent, "", w, function(self)
		Eco.Dropdown.Open(self)
	end)
	return b
end

function B.SetDropdown(b, options, selected, onPick)
	Eco.Dropdown.Set(b, options, selected, function(v)
		onPick(v)
		Eco.Refresh()
	end)
end

-- a list of the book (Widgets), dressed by the theme
function B.List(parent, columns, sortCol, rowH)
	local list = Eco.NewList(parent, columns, sortCol, rowH or 28)
	T.Skin(list, "list")
	return list
end

-- money: gold, silver, copper (Eco.Money); signed: + / - always written
function B.Money(c)
	return Eco.Money(c)
end

function B.Signed(c)
	if not c then
		return "|cff808080?|r"
	end
	return (c > 0 and "+" or (c < 0 and "-" or "")) .. Eco.Money(math.abs(c))
end

-- a result: its sign, its colour, a word with it
function B.Result(fs, c, unknownText)
	if c == nil then
		fs:SetText(unknownText or "Not enough data")
		B.Paint(fs, "uncertain")
	else
		fs:SetText(B.Signed(c) .. (c > 0 and "  (profit)" or (c < 0 and "  (loss)" or "")))
		B.Paint(fs, c > 0 and "positive" or (c < 0 and "negative" or "ink"))
	end
end

-- data quality in words with its marks: 0 not enough data .. 3 good
local QUALITY_COLOUR = { [0] = "negative", "uncertain", "uncertain", "positive" }
local MARKS = { [0] = "-", "*", "**", "***" }
function B.QualityText(level)
	local r, g, b = T.Color(QUALITY_COLOUR[level] or "muted")
	return format("|cff%02x%02x%02x%s %s|r", r * 255, g * 255, b * 255, MARKS[level] or "", Eco.QUALITY[level] or "?")
end

-- colour codes for a list cell (colours meant for a dark ground: the list
-- adapts them to its page)
B.GREEN, B.RED, B.AMBER, B.GREY = { 0.3, 1, 0.3 }, { 1, 0.35, 0.35 }, { 1, 0.75, 0.2 }, { 0.6, 0.6, 0.6 }

------------------------------------------------------------------------
-- The pages
--   page = { key, label, icon, order, Create(page), Refresh(page),
--   OnKey(page, key) }; page.L, page.R: its frames on the left and the
--   right page, page.S: across both (wide tables, sheets); B.Spread(page,
--   on) chooses
------------------------------------------------------------------------

function B.Register(page)
	B.pages[page.key] = page
	B.order[#B.order + 1] = page
	table.sort(B.order, function(a, b)
		return a.order < b.order
	end)
	page.state = page.state or {}
	return page
end

function B.Spread(page, on)
	page.spread = on and true or false
	if B.state.page == page.key and B.frame then
		B.ShowContainers()
	end
end

function B.ShowContainers()
	local f = B.frame
	local cur = B.state.page
	local settings = B.state.settings
	for key, page in pairs(B.pages) do
		local open = key == cur and not settings
		if page.L then
			page.L:SetShown(open and not page.spread)
			page.R:SetShown(open and not page.spread)
			page.S:SetShown(open and page.spread)
		end
	end
	local spread = settings or (B.pages[cur] and B.pages[cur].spread)
	f.spine:SetShown(not spread)
	f.seam:SetShown(spread and true or false)
	f.settings:SetShown(settings and true or false)
    f.left:SetShown(not settings);f.right:SetShown(not settings)
end

-- open a page (its state kept)
function B.Open(key)
	if not B.pages[key] then
		key = "overview"
	end
	B.state.page = key
	B.state.settings = false
	DB().settings.ledgerPage = key
	for _, tab in ipairs(B.frame.tabs) do
		tab.wc3cOn = tab.key == key
		T.TabState(tab)
	end
	B.ShowContainers()
	Eco.Refresh()
end

------------------------------------------------------------------------
-- The window
------------------------------------------------------------------------

local function Bookmark(f,page,i)
    local b=B.Button(f,page.label,156,function() B.Open(page.key) end,30)
    b.key=page.key; b.wc3cLabel=b:GetFontString()
    B.Tip(b,page.label,page.about)
    return b
end

-- whose fortune: this character, all of them (this realm and side), one
local function ScopeOptions()
	local me = ns.CharKey()
	local options = { { value = "char", label = "This character (" .. (me:match("^[^-]+") or me) .. ")" }, { value = "all", label = "All my characters here" } }
	for _, key in ipairs(Eco.OwnCharacters()) do
		if key ~= me then
			options[#options + 1] = { value = key, label = key:match("^[^-]+") or key }
		end
	end
	return options
end

function B.Scope()
	return DB().settings.ledgerScope or "char"
end

local function Header(f)
	local h = CreateFrame("Frame", nil, f)
	h:SetPoint("TOPLEFT", BORDER, -16)
	h:SetPoint("TOPRIGHT", -BORDER, -16)
	h:SetHeight(44)
	f.header = h
	local coin = h:CreateTexture(nil, "ARTWORK")
	coin:SetSize(30, 30)
	coin:SetPoint("LEFT", 4, 0)
	T.Skin(coin, "coin")
	local title = B.Text(h, "bookTitle")
	title:SetPoint("TOPLEFT", 40, 0)
	title:SetText("The Goblin Ledger")
	f.title = title
	-- (the market under the title: realm and side)
	f.market = B.Text(h, "coverMuted")
	f.market:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 1, -1)
	B.Tip(f.market, "Market", "The realm and the side of the auction house these prices belong to (the last auction house opened).")
	-- right, from the edge: close, settings, scan, its status, whose fortune
	local close
	local ok, cb = pcall(CreateFrame, "Button", nil, h, "UIPanelCloseButton")
	if ok and cb then
		close = cb
	else
		close = B.Button(h, "X", 24)
	end
	close:SetPoint("RIGHT", 2, 0)
	close:SetScript("OnClick", function()
		f:Hide()
	end)
	local gear = B.Button(h, "Settings", 80, function()
		B.state.settings = not B.state.settings
		B.ShowContainers()
		if B.state.settings then
			B.RefreshSettings()
		else
			Eco.Refresh()
		end
	end)
	gear:SetPoint("RIGHT", close, "LEFT", -4, 0)
	B.Tip(gear, "Settings", "Appearance (theme, size), the settings of each way to make gold, the data of this market.")
	f.gear = gear
	local scan = B.Button(h, "Scan", 92, Eco.Scan)
	scan:SetPoint("RIGHT", gear, "LEFT", -8, 0)
	scan:HookScript("OnEnter", Eco.View.ScanTooltip)
	Eco.scanButtons[#Eco.scanButtons + 1] = scan
	f.scan = scan
	f.status = B.Text(h, "coverMuted", "RIGHT")
	f.status:SetPoint("RIGHT", scan, "LEFT", -8, 0)
	f.status:SetWidth(170)
	local zone = CreateFrame("Frame", nil, h)
	zone:SetAllPoints(f.status)
	zone:EnableMouse(true)
	B.Tip(zone, "Last scan", function()
		return Eco.ScanStatusLong and Eco.ScanStatusLong() or ""
	end)
	f.scope = B.Dropdown(h, 176)
	f.scope:SetPoint("TOPRIGHT", f, "TOPRIGHT", -22, -68)
	B.Tip(f.scope, "Whose fortune", "This character, or every character of yours on this realm and side (their gold as last seen, their ledgers).")
end

local function Footer(f)
	local hint = B.Text(f, "coverMuted")
	hint:SetPoint("BOTTOMLEFT", BORDER + 6, 6)
	hint:SetPoint("BOTTOMRIGHT", -TABS_W - 20, 6)
	hint:SetText("Esc: close   Click tabs to navigate   Click an opportunity for details")
	f.hint = hint
	-- resize grip
	local grip = CreateFrame("Button", nil, f)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -4, 4)
	grip:SetNormalTexture([[Interface\ChatFrame\UI-ChatIM-SizeGrabber-Up]])
	grip:SetHighlightTexture([[Interface\ChatFrame\UI-ChatIM-SizeGrabber-Highlight]])
	grip:SetPushedTexture([[Interface\ChatFrame\UI-ChatIM-SizeGrabber-Down]])
	grip:SetScript("OnMouseDown", function()
		f.moving = true
		f:StartSizing("BOTTOMRIGHT")
	end)
	grip:SetScript("OnMouseUp", function()
		f:StopMovingOrSizing()
		f.moving = false
		B.SavePlace()
	end)
end

-- where the window is: kept (its top left corner and its size)
function B.SavePlace()
	local f = B.frame
	local left, top = f:GetLeft(), f:GetTop()
	if left and top then
		DB().pos = { x = floor(left + 0.5), y = floor(top + 0.5), w = floor(f:GetWidth() + 0.5), h = floor(f:GetHeight() + 0.5) }
	end
end

-- the scale of the book (Appearance > Size)
function B.ApplyScale()
	local s = DB().settings.ledgerScale or 1
	s = max(0.7, min(1.3, s))
	local w,h=UIParent:GetWidth(),UIParent:GetHeight()
    if w and h and w>0 and h>0 then
        s=min(s,(w-24)/B.frame:GetWidth(),(h-24)/B.frame:GetHeight())
    end
    B.frame:SetScale(s)
end

-- the theme (Appearance > Theme): every part dressed again, the pages
-- drawn again with the same state
function B.SetTheme(key)
	local st = DB().settings
	st.theme = T.Set(key)
	Eco.Refresh()
	if B.state.settings then
		B.RefreshSettings()
	end
end

------------------------------------------------------------------------
-- Settings (a page of their own over both pages)
------------------------------------------------------------------------

local function Section(parent, text, y, x)
	local fs = B.Text(parent, "heading")
	fs:SetPoint("TOPLEFT", x or PAD, y)
	fs:SetText(text)
	local line = B.Line(parent)
	line:SetHeight(1)
	B.Span(line, parent, y - 17, x or PAD, PAD)
	return fs
end

local function Settings(f)
	local s = CreateFrame("Frame", nil, f)
    s:SetPoint("TOPLEFT",BORDER,-HEADER);s:SetPoint("BOTTOMRIGHT",-BORDER,FOOTER)
    T.Skin(s,"settingsPanel")
	s:SetFrameLevel(f.content:GetFrameLevel())
	s:Hide()
	f.settings = s
	local st = DB().settings
	local title = B.Text(s, "title")
	title:SetPoint("TOPLEFT", PAD, -PAD)
	title:SetText("Settings")
	local back = B.Button(s, "Back to the book", 140, function()
		B.state.settings = false
		B.ShowContainers()
		Eco.Refresh()
	end)
	back:SetPoint("TOPRIGHT", -PAD, -PAD)

	-- left column: Appearance
	local col = CreateFrame("Frame", nil, s)
	col:SetPoint("TOPLEFT", 0, -52)
	col:SetPoint("BOTTOMRIGHT", s, "BOTTOM", -SPINE_W / 2, 0)
	Section(col, "Appearance  >  Theme", 0)
	s.themes = {}
	for i, key in ipairs(T.ORDER) do
		local th = T.THEMES[key]
		local b = B.Button(col, th.label, 200, function()
			B.SetTheme(key)
		end)
		b:SetPoint("TOPLEFT", PAD, -24 - (i - 1) * 60)
		local about = B.Text(col, "muted")
		about:SetWordWrap(true)
		about:SetJustifyV("TOP")
		B.Span(about, col, -24 - (i - 1) * 60 - 26, PAD + 2, PAD)
		about:SetHeight(30)
		about:SetText(th.about)
		b.key = key
		s.themes[i] = b
	end
	Section(col, "Appearance  >  Size", -212)
	local smaller = B.Button(col, "Smaller", 80, function()
		st.ledgerScale = max(0.7, (st.ledgerScale or 1) - 0.05)
		B.ApplyScale()
		B.RefreshSettings()
	end)
	smaller:SetPoint("TOPLEFT", PAD, -236)
	local larger = B.Button(col, "Larger", 80, function()
		st.ledgerScale = min(1.3, (st.ledgerScale or 1) + 0.05)
		B.ApplyScale()
		B.RefreshSettings()
	end)
	larger:SetPoint("LEFT", smaller, "RIGHT", 6, 0)
	s.scale = B.Text(col, "body")
	s.scale:SetPoint("LEFT", larger, "RIGHT", 10, 0)
	local reset = B.Button(col, "Place it again", 120, function()
		DB().pos = nil
		st.ledgerScale = 1
		B.ApplyScale()
		Eco.Place(true)
		B.RefreshSettings()
	end)
	reset:SetPoint("TOPLEFT", smaller, "BOTTOMLEFT", 0, -8)
	B.Tip(reset, "Place it again", "Size 100 %, beside the auction house, the size the screen allows.")
	Section(col, "Data", -302)
	local textures = B.Button(col, "Check the textures", 150, function()
		T.Report()
	end)
	textures:SetPoint("TOPLEFT", PAD, -326)
	B.Tip(textures, "Check the textures", "Lists in the chat what the themes need and whether this client has it.")
	local purge = B.Button(col, "Erase this market's prices", 190, function(self)
		if self.armed then
			self.armed = false
			Eco.Purge()
			self:SetText("Erase this market's prices")
			ns.Print("prices of this market erased (your trades are kept).")
		else
			self.armed = true
			self:SetText("Click again to erase")
		end
	end)
	purge:SetPoint("LEFT", textures, "RIGHT", 8, 0)
	B.Tip(purge, "Erase this market's prices", "The price history of this realm and side (a wipe, a new server). Your ledgers and your gold history stay. Two clicks.")

	-- right column: the settings of the methods
	local right = CreateFrame("Frame", nil, s)
	right:SetPoint("TOPLEFT", s, "TOP", SPINE_W / 2, -52)
	right:SetPoint("BOTTOMRIGHT", 0, 0)
	s.boxes, s.checks = {}, {}
	local function Box(parent, label, x, y, w, get, set, tip)
		local fs = B.Text(parent, "body")
		fs:SetPoint("TOPLEFT", x, y - 3)
		fs:SetText(label)
		local box = B.Number(parent, w, get, set)
		box:SetPoint("LEFT", fs, "RIGHT", 8, 0)
		if tip then
			B.Tip(box, label, tip)
		end
		s.boxes[#s.boxes + 1] = box
		return box
	end
	local function Check(parent, label, x, y, key)
		local c = B.Check(parent, label, function()
			return st[key]
		end, function(v)
			st[key] = v
			Eco.Refresh()
		end)
		c:SetPoint("TOPLEFT", x, y)
		s.checks[#s.checks + 1] = c
		return c
	end
	-- (one setting a row: nothing cut on a small book)
	local y = 0
	local function Row(h)
		local at = y
		y = y - (h or 24)
		return at
	end
	Section(right, "Buy & Resell", Row(26))
	Box(right, "Return at least (%)", PAD, Row(), 40, function()
		return tostring(st.minReturn)
	end, function(v)
		st.minReturn = min(300, max(0, floor(v)))
	end, "Net return wanted on the purchase price, after the cut and the deposits.")
	Box(right, "Budget (gold, 0: your gold)", PAD, Row(), 56, function()
		return tostring(st.budget)
	end, function(v)
		st.budget = max(0, floor(v))
	end, "Gold set aside for trading (0: your gold + your stock). Half stays free; per item 1 % while testing, 5 % once proven.")
	Box(right, "Failed posts to cover", PAD, Row(), 40, function()
		return tostring(st.failures)
	end, function(v)
		st.failures = min(10, max(0, floor(v)))
	end, "Deposits of this many failed posts are counted in the cost of a resale.")
	local row = Row()
	Check(right, "Stackables only", PAD, row, "stackOnly")
	Check(right, "Show risky ones", PAD + 160, row, "showRisky")
	Section(right, "Craft & Sell", Row(26) - 4)
	row = Row()
	Check(right, "Profitable only", PAD, row, "onlyProfit")
	Check(right, "Hide soulbound", PAD + 160, row, "hideBound")
	Section(right, "Disenchant  /  Craft & Disenchant", Row(26) - 4)
	Box(right, "Model chance asked (%)", PAD, Row(), 40, function()
		return tostring(st.deChance)
	end, function(v)
		st.deChance = min(99, max(50, floor(v)))
	end, "A disenchant gives its materials by chance: a lot is sized for this chance of a profit, under the model's assumptions (not a guarantee).")
	Box(right, "Return at least (%)", PAD, Row(), 40, function()
		return tostring(st.deReturn)
	end, function(v)
		st.deReturn = min(500, max(5, floor(v)))
	end, "Each item bought: its disenchant's mean value against its price.")
	Box(right, "Profit at least (gold)", PAD, Row(), 52, function()
		return format("%.2f", st.deMinProfit / 10000)
	end, function(v)
		st.deMinProfit = max(0, floor(v * 10000 + 0.5))
	end, "Expected profit of a lot, without a capital.")
	Box(right, "Capital (gold)", PAD, Row(), 52, function()
		return format("%g", st.deCapital / 10000)
	end, function(v)
		st.deCapital = max(0, floor(v * 10000 + 0.5))
	end, "0: the smallest safe lot of each kind. Else a plan sized to it (advised lots only).")
	Check(right, "Show the estimates (lots not advised)", PAD, Row(), "deAll")
	B.SettingsFrame = s
end

function B.RefreshSettings()
	B.LayoutDock()
	local s = B.frame.settings
	local st = DB().settings
	for _, b in ipairs(s.themes) do
		B.SetOn(b, b.key == st.theme)
	end
	s.scale:SetText(format("%d %%", floor((st.ledgerScale or 1) * 100 + 0.5)))
	for _, box in ipairs(s.boxes) do
		if not box:HasFocus() then
			box:Sync()
		end
	end
	for _, c in ipairs(s.checks) do
		c:Refresh()
	end
end

------------------------------------------------------------------------
-- Keyboard (out of combat only: a key the book does not use goes on to
-- the game; in combat every key goes on)
------------------------------------------------------------------------

local function OnKey(f, key)
	if InCombatLockdown() then
		return
	end
	local used = false
	local page = B.pages[B.state.page]
	if key == "TAB" and not B.state.settings then
		local i = 1
		for n, p in ipairs(B.order) do
			if p.key == B.state.page then
				i = n
			end
		end
		i = IsShiftKeyDown() and (i - 2) % #B.order + 1 or i % #B.order + 1
		B.Open(B.order[i].key)
		used = true
	elseif page and page.OnKey and not B.state.settings then
		used = page:OnKey(key) and true or false
	end
	f:SetPropagateKeyboardInput(not used)
	-- (a key used stops that key only: the next frame every key goes on
	-- again, so that the book never holds the keys when a combat starts)
	if used and not f.wc3cKeysBack then
		f.wc3cKeysBack = true
		C_Timer.After(0, function()
			f.wc3cKeysBack = false
			if not InCombatLockdown() then
				f:SetPropagateKeyboardInput(true)
			end
		end)
	end
end

-- a list moved by the keys: Up / Down select, Right opens (onOpen)
function B.ListKey(list, key, onOpen)
	local data = list.data
	if #data == 0 then
		return false
	end
	local index
	for i, d in ipairs(data) do
		if d.key == list.selected then
			index = i
		end
	end
	if key == "DOWN" or key == "UP" then
		index = index and (index + (key == "DOWN" and 1 or -1)) or 1
		index = max(1, min(#data, index))
		list.selected = data[index].key
		if index <= list.offset then
			list:ScrollTo(index - 1)
		elseif index > list.offset + list.visible then
			list:ScrollTo(index - list.visible)
		end
		list:Refresh()
		return true
	elseif key == "RIGHT" and index and onOpen then
		onOpen(data[index])
		return true
	end
	return false
end

------------------------------------------------------------------------
-- Making the book
------------------------------------------------------------------------

function B.Create()
	if B.frame then
		return B.frame
	end
	local f = CreateFrame("Frame", "WC3C_Economy", UIParent)
	B.frame = f
	Eco.frame = f
	f:Hide()
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetResizable(true)
	if f.SetResizeBounds then
		f:SetResizeBounds(MIN_W, MIN_H, 1800, 1100)
	elseif f.SetMinResize then
		f:SetMinResize(MIN_W, MIN_H)
	end
	f:SetSize(DEFAULT_W, DEFAULT_H)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self)
		self.moving = true
		self:StartMoving()
	end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		if self.SetUserPlaced then
			self:SetUserPlaced(false)
		end
		self.moving = false
		B.SavePlace()
	end)
	tinsert(UISpecialFrames, "WC3C_Economy")
	T.Skin(f, "cover")
	Header(f)

	-- the open book: two pages, the spine between them
	local book = CreateFrame("Frame", nil, f)
	book:SetPoint("TOPLEFT", BORDER, -HEADER)
	book:SetPoint("BOTTOMRIGHT", -TABS_W, FOOTER)
	f.book = book
	f.left = CreateFrame("Frame", nil, book)
	f.left:SetPoint("TOPLEFT")
	f.left:SetPoint("BOTTOMRIGHT", book, "BOTTOM", 0, 0)
	f.right = CreateFrame("Frame", nil, book)
	f.right:SetPoint("TOPLEFT", book, "TOP", 0, 0)
	f.right:SetPoint("BOTTOMRIGHT")
	T.Skin(f.left, "page", "left")
	T.Skin(f.right, "page", "right")
	local spine = book:CreateTexture(nil, "BORDER", nil, 2)
	spine:SetPoint("TOP", book, "TOP", 0, 0)
	spine:SetPoint("BOTTOM", book, "BOTTOM", 0, 0)
	spine:SetWidth(SPINE_W * 2)
	T.Skin(spine, "spine")
	f.spine = spine
	-- (pages across the book: a thin seam only, no ornament under the figures)
	local seam = book:CreateTexture(nil, "BORDER", nil, 2)
	seam:SetPoint("TOP", book, "TOP", 0, -6)
	seam:SetPoint("BOTTOM", book, "BOTTOM", 0, 6)
	seam:SetWidth(1)
	T.Skin(seam, "line")
	seam:SetAlpha(0)
	f.seam = seam
	-- the pages' frames (content above the paper)
	local content = CreateFrame("Frame", nil, book)
	content:SetAllPoints()
	content:SetFrameLevel(book:GetFrameLevel() + 5)
	f.content = content
	for _, page in ipairs(B.order) do
		page.L = CreateFrame("Frame", nil, content)
		page.L:SetPoint("TOPLEFT", PAD, -PAD)
		page.L:SetPoint("BOTTOMRIGHT", content, "BOTTOM", -SPINE_W / 2 - 4, PAD)
		page.R = CreateFrame("Frame", nil, content)
		page.R:SetPoint("TOPLEFT", content, "TOP", SPINE_W / 2 + 4, -PAD)
		page.R:SetPoint("BOTTOMRIGHT", -PAD, PAD)
		page.S = CreateFrame("Frame", nil, content)
		page.S:SetPoint("TOPLEFT", PAD, -PAD)
		page.S:SetPoint("BOTTOMRIGHT", -PAD, PAD)
		page.L:Hide()
		page.R:Hide()
		page.S:Hide()
	end
	-- bookmarks on the right edge
	f.tabs = {}
	for i, page in ipairs(B.order) do
		local tab = Bookmark(f, page, i)
		tab:SetPoint("TOPLEFT", f, "TOPLEFT", 22 + (i - 1) * 162, -68)
		f.tabs[i] = tab
	end
	Footer(f)
	Settings(f)
    f.toolbar=CreateFrame("Frame",nil,f)
    f.toolbar:SetPoint("TOPLEFT",22,-HEADER);f.toolbar:SetPoint("TOPRIGHT",-22,-HEADER)
    f.toolbar:SetHeight(36)
    f:HookScript("OnSizeChanged",B.QueueDock)
    for _,page in ipairs(B.order) do
        B.buildingPage=page
        page:Create(page)
        B.buildingPage=nil
    end
    local captions={deBudget={"Budget (gold)","deBudgetLabel"},deMargin={"Min. margin %","deMarginLabel"},goalBox={"Goal (gold)"},saleNet={"Net sale (gold)"},saleLoss={"Lost fees (gold)"},searchBox={"Search"},exclusionTerms={"Exclude words"}}
    for _,page in ipairs(B.order) do
        for field,info in pairs(captions) do
            for _,entry in ipairs(page.dockControls or {}) do
                if page[field]==entry.control then entry.caption=info[1];entry.label=info[2] and page[info[2]] end
            end
        end
    end
	-- The ledger does not capture gameplay keys; edit boxes keep their native handling.
	f:EnableKeyboard(false)
	f:SetPropagateKeyboardInput(true)
	f:HookScript("OnHide", function()
		Eco.Dropdown.Close()
	end)
	f:HookScript("OnShow", function()
		T.Load()
		B.ApplyScale()
		Eco.Place(true)
		B.Open(B.state.page or DB().settings.ledgerPage or "overview")
	end)
	-- follow the auction house and the bags while open; the scan status
	local tick, statusTick = 0, 0
	f:SetScript("OnUpdate", function(_, elapsed)
		tick, statusTick = tick + elapsed, statusTick + elapsed
		if tick >= 0.3 then
			tick = 0
			Eco.Place()
		end
		if statusTick >= 5 then
			statusTick = 0
			Eco.UpdateStatus()
		end
	end)
    local st=DB().settings
    if st.retailLedgerVersion ~= 1 then
        DB().pos=nil
        st.ledgerScale=1
        st.retailLedgerVersion=1
    end
	T.Load()
	return f
end

-- the header: market, scope, status
function B.RefreshHeader()
	local f = B.frame
	local st = DB().settings
	f.market:SetText(Eco.MarketLabel())
	local scope = st.ledgerScope
	local options = ScopeOptions()
	local found = false
	for _, o in ipairs(options) do
		found = found or o.value == scope
	end
	if not found then
		st.ledgerScope, scope = "char", "char"
	end
	B.SetDropdown(f.scope, options, scope, function(v)
		st.ledgerScope = v
	end)
end

-- draw the open page again (its state kept)
function B.Refresh()
	local f = B.frame
	if not (f and f:IsShown()) then
		return
	end
	Eco.OppReset()
	B.RefreshHeader()
	if B.state.settings then
		B.RefreshSettings()
        B.LayoutDock()
		return
	end
	local page = B.pages[B.state.page]
	if page and page.Refresh then
		ns.Try("ledger " .. page.key, page.Refresh, page)
        B.LayoutDock()
	end
end
