--[[
	WC3 Console - economy: the widgets of the window (list, number box,
	dropdown, chart)
]]

local _, ns = ...
local Eco = ns.Economy
local floor, max, min = math.floor, math.max, math.min
local ipairs, tostring, unpack = ipairs, tostring, unpack or table.unpack
local sort = table.sort

local ROW_H = 18

------------------------------------------------------------------------
-- List widget: sortable columns, virtual rows, mouse wheel, scroll bar
--   column: label, width (0: shares the free width), align, desc (sorted
--   high to low first), text(d) -> text, r, g, b, sort(d) -> value,
--   icon(d) -> texture (first column)
------------------------------------------------------------------------

local List = {}
List.__index = List

-- (rowH: the height of a row, default 18; a theme dresses it: List:Skin)
function Eco.NewList(parent, columns, sortCol, rowH)
	local ROW_H = rowH or ROW_H
	local t = setmetatable({ columns = columns, rows = {}, data = {}, offset = 0, visible = 0, sortCol = sortCol, sortDesc = true, rowH = ROW_H }, List)
	local f = CreateFrame("Frame", nil, parent)
	t.frame = f
	f:EnableMouseWheel(true)
	f:SetScript("OnMouseWheel", function(_, delta)
		t:ScrollTo(t.offset - delta * 3)
	end)
	f:SetScript("OnSizeChanged", function()
		t:Layout()
	end)
	t.headers = {}
	for i, col in ipairs(columns) do
		local h = CreateFrame("Button", nil, f)
		h:SetHeight(ROW_H)
		h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		h.text:SetPoint("LEFT", 4, 0)
		h.text:SetPoint("RIGHT", -4, 0)
		h.text:SetJustifyH(col.align or "LEFT")
		h.text:SetText(col.label)
		h:SetHighlightTexture([[Interface\QuestFrame\UI-QuestTitleHighlight]], "ADD")
		h:SetScript("OnClick", function()
			t:SortBy(i)
		end)
		-- (what the column means)
		if col.tip then
			h:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_TOP")
				GameTooltip:AddLine(col.label, 1, 0.82, 0)
				GameTooltip:AddLine(col.tip, 1, 1, 1, true)
				GameTooltip:Show()
			end)
			h:SetScript("OnLeave", function()
				GameTooltip:Hide()
			end)
		end
		t.headers[i] = h
	end
	local line = f:CreateTexture(nil, "ARTWORK")
	t.line = line
	line:SetColorTexture(0.75, 0.6, 0.25, 0.5)
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", 0, -ROW_H)
	line:SetPoint("TOPRIGHT", 0, -ROW_H)
	local bar = CreateFrame("Slider", nil, f)
	bar:SetOrientation("VERTICAL")
	bar:SetWidth(8)
	bar:SetPoint("TOPRIGHT", 0, -ROW_H - 2)
	bar:SetPoint("BOTTOMRIGHT", 0, 0)
	local track = bar:CreateTexture(nil, "BACKGROUND")
	t.track = track
	track:SetAllPoints()
	track:SetColorTexture(0, 0, 0, 0.35)
	local thumb = bar:CreateTexture(nil, "OVERLAY")
	t.thumb = thumb
	thumb:SetColorTexture(0.75, 0.6, 0.25, 0.9)
	thumb:SetSize(6, 28)
	bar:SetThumbTexture(thumb)
	bar:SetValueStep(1)
	bar:SetMinMaxValues(0, 0)
	bar:EnableMouse(true)
	bar:SetScript("OnValueChanged", function(_, v)
		t:ScrollTo(v)
	end)
	t.bar = bar
	t.empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	t.empty:SetPoint("LEFT", 20, -ROW_H / 2)
	t.empty:SetPoint("RIGHT", -20, -ROW_H / 2)
	t.empty:SetJustifyH("CENTER")
	return t
end

function List:NewRow(i)
	local ROW_H = self.rowH
	local c = self.colors
	local row = CreateFrame("Button", nil, self.frame)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.stripe = row:CreateTexture(nil, "BACKGROUND")
	row.stripe:SetAllPoints()
	row.stripe:SetColorTexture(unpack(c and c.stripe or { 1, 1, 1, 0.035 }))
	row.stripe:SetShown(i % 2 == 0)
	row.sel = row:CreateTexture(nil, "BACKGROUND", nil, 1)
	row.sel:SetAllPoints()
	row.sel:SetColorTexture(unpack(c and c.sel or { 1, 0.82, 0, 0.15 }))
	row.sel:Hide()
	row:SetHighlightTexture([[Interface\QuestFrame\UI-QuestTitleHighlight]], "ADD")
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ROW_H - 2, ROW_H - 2)
	row.icon:SetPoint("LEFT", 2, 0)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	row.cells = {}
	for c, col in ipairs(self.columns) do
		local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		if self.font then
			fs:SetFont(self.font[1], self.font[2], "")
			fs:SetShadowOffset(self.font[3] or 0, -(self.font[3] or 0))
		end
		fs:SetJustifyH(col.align or "LEFT")
		fs:SetWordWrap(false)
		row.cells[c] = fs
	end
	row:SetScript("OnClick", function(r, button)
		if r.data and self.onClick then
			self.onClick(r.data, button)
		end
	end)
	row:SetScript("OnEnter", function(r)
		if r.data and self.onEnter then
			self.onEnter(r, r.data)
		end
	end)
	row:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	self.rows[i] = row
	return row
end

function List:Layout()
	local ROW_H = self.rowH
	local f = self.frame
	local w, h = f:GetWidth(), f:GetHeight()
	if not w or w <= 1 or not h or h <= 1 then
		return
	end
	local width = w - 12 -- scroll bar
	local fixed, flex = 0, 0
	for _, col in ipairs(self.columns) do
		if col.width > 0 then
			fixed = fixed + col.width
		else
			flex = flex + 1
		end
	end
	local budget = max(1,width)
    local factor = min(1,budget / max(1,fixed + flex*130))
    local flexW = max(1,(budget-fixed*factor)/max(1,flex))
	local x = 0
	for i, col in ipairs(self.columns) do
		col.x, col.w = x, col.width > 0 and col.width*factor or flexW
		local hd = self.headers[i]
		hd:ClearAllPoints()
		hd:SetPoint("TOPLEFT", f, "TOPLEFT", x, 0)
		hd:SetWidth(col.w)
		x = x + col.w
	end
	local n = max(1, floor((h - ROW_H - 2) / ROW_H))
	for i = 1, n do
		local row = self.rows[i] or self:NewRow(i)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -ROW_H - 2 - (i - 1) * ROW_H)
		row:SetSize(width, ROW_H)
		for c, col in ipairs(self.columns) do
			local pad = col.icon and (ROW_H + 2) or 4
			local fs = row.cells[c]
			fs:ClearAllPoints()
			fs:SetPoint("LEFT", row, "LEFT", col.x + pad, 0)
			fs:SetWidth(max(1, col.w - pad - 4))
			if col.icon then
				row.icon:ClearAllPoints()
				row.icon:SetPoint("LEFT", row, "LEFT", col.x + 2, 0)
			end
		end
	end
	for i = n + 1, #self.rows do
		self.rows[i]:Hide()
		self.rows[i].data = nil
	end
	self.visible = n
	self:Refresh()
end

function List:ScrollTo(v)
	local maxOff = max(0, #self.data - self.visible)
	v = min(maxOff, max(0, floor(v + 0.5)))
	if v ~= self.offset then
		self.offset = v
		self:Refresh()
	end
end

function List:Refresh()
	local data = self.data
	local maxOff = max(0, #data - self.visible)
	if self.offset > maxOff then
		self.offset = maxOff
	end
	self.bar:SetMinMaxValues(0, maxOff)
	self.bar:SetValue(self.offset)
	self.bar:SetShown(maxOff > 0)
	for i, col in ipairs(self.columns) do
		local hd = self.headers[i]
		local c = self.colors
		if i == self.sortCol then
			hd.text:SetTextColor(unpack(c and c.sorted or { 1, 1, 1 }))
		else
			hd.text:SetTextColor(unpack(c and c.header or { 1, 0.82, 0 }))
		end
	end
	local iconCol
	for _, col in ipairs(self.columns) do
		iconCol = iconCol or col.icon
	end
	for i = 1, self.visible do
		local row = self.rows[i]
		local d = data[self.offset + i]
		row.data = d
		if d then
			for c, col in ipairs(self.columns) do
				local text, r, g, b = col.text(d)
				local fs = row.cells[c]
				fs:SetText(text or "")
				-- (colours meant for a dark ground: the list's ink on its page)
				if self.Ink then
					fs:SetTextColor(self.Ink(r or 1, g or 1, b or 1))
				else
					fs:SetTextColor(r or 1, g or 1, b or 1)
				end
			end
			if iconCol then
				row.icon:SetTexture(iconCol(d))
				row.icon:Show()
			else
				row.icon:Hide()
			end
			row.sel:SetShown(self.selected ~= nil and self.selected == d.key)
			row:Show()
		else
			row:Hide()
		end
	end
	self.empty:SetShown(#data == 0)
end

function List:Sort()
	local col = self.columns[self.sortCol or 1]
	local get, desc = col.sort, self.sortDesc
	if not get then
		return
	end
	sort(self.data, function(a, b)
		local x, y = get(a), get(b)
		if x == nil or y == nil then
			if x == nil and y == nil then
				return tostring(a.key) < tostring(b.key)
			end
			return y == nil -- unknown values last
		end
		if x == y then
			return tostring(a.key) < tostring(b.key)
		end
		if desc then
			return x > y
		end
		return x < y
	end)
end

function List:SortBy(i)
	if self.sortCol == i then
		self.sortDesc = not self.sortDesc
	else
		self.sortCol, self.sortDesc = i, self.columns[i].desc ~= false
	end
	self:Sort()
	self:Refresh()
end

function List:SetData(data)
	self.data = data
	self:Sort()
	if self.visible == 0 then
		self:Layout()
	end
	self:Refresh()
end

-- Dress the list for a theme (Eco.Theme): header, line, stripes, selection,
-- scroll bar, empty text, the ink of its cells (fonts: the theme's); in
-- place, its rows, data, sort, selection and scrolling stay
function List:Skin(th)
	local T = Eco.Theme
	local function C(name)
		return { T.Color(name) }
	end
	self.colors = { header = C("title"), sorted = C("ink"), stripe = C("rowAlt"), sel = C("select") }
	self.Ink = T.Ink
	local file = T.FONTS.body[1]
	self.font = { _G.STANDARD_TEXT_FONT or file, 13, th.light and 0 or 1 }
	self.line:SetColorTexture(T.Color("line"))
	self.track:SetColorTexture(0, 0, 0, th.light and 0.12 or 0.35)
	self.thumb:SetColorTexture(T.Color("scroll"))
	self.empty:SetTextColor(T.Color("muted"))
	self.empty:SetShadowOffset(th.light and 0 or 1, th.light and 0 or -1)
	for _, h in ipairs(self.headers) do
		h.text:SetShadowOffset(th.light and 0 or 1, th.light and 0 or -1)
	end
	for i, row in ipairs(self.rows) do
		row.stripe:SetColorTexture(unpack(self.colors.stripe))
		row.sel:SetColorTexture(unpack(self.colors.sel))
		for _, fs in ipairs(row.cells) do
			fs:SetFont(self.font[1], self.font[2], "")
			fs:SetShadowOffset(self.font[3], -self.font[3])
		end
	end
	self:Refresh()
end

-- a number typed in a box (applied when the box loses the focus)
function Eco.NumberBox(parent, width, get, set)
	local ok, b = pcall(CreateFrame, "EditBox", nil, parent, "InputBoxTemplate")
	if not ok or not b then
		b = CreateFrame("EditBox", nil, parent)
		local bg = b:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0, 0, 0, 0.5)
		b:SetFontObject("GameFontHighlightSmall")
	end
	b:SetSize(width, 18)
	b:SetAutoFocus(false)
	b:SetJustifyH("CENTER")
	b.Sync = function(self)
		self:SetText(get())
	end
	b:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
	end)
	b:SetScript("OnEscapePressed", function(self)
		self:Sync()
		self:ClearFocus()
	end)
	b:SetScript("OnEditFocusLost", function(self)
		local v = tonumber(self:GetText())
		if v then
			set(v)
		end
		self:Sync()
		Eco.Refresh()
	end)
	return b
end

function Eco.Label(parent, text)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	fs:SetText(text)
	return fs
end

-- a button that opens a list of choices (with their counts)
local Dropdown = {}
do
	local menu, catcher
	local function Menu()
		if menu then
			return menu
		end
		-- a click anywhere else closes the list
		catcher = CreateFrame("Button", nil, UIParent)
		catcher:SetAllPoints(UIParent)
		catcher:SetFrameStrata("FULLSCREEN_DIALOG")
		catcher:Hide()
		menu = CreateFrame("Frame", nil, UIParent)
		menu:SetFrameStrata("FULLSCREEN_DIALOG")
		menu:SetFrameLevel((catcher:GetFrameLevel() or 0) + 10)
		menu:EnableMouse(true)
		local bg = menu:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0.05, 0.04, 0.03, 0.96)
		for _, p in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
			local edge = menu:CreateTexture(nil, "BORDER")
			edge:SetColorTexture(0.75, 0.6, 0.25, 1)
			edge:SetPoint(p[1])
			edge:SetPoint(p[2])
			if p[1] == "TOPLEFT" and p[2] == "BOTTOMLEFT" or p[1] == "TOPRIGHT" then
				edge:SetWidth(1)
			else
				edge:SetHeight(1)
			end
		end
		menu.rows = {}
		menu:SetScript("OnHide", function()
			catcher:Hide()
		end)
		catcher:SetScript("OnClick", function()
			menu:Hide()
		end)
		menu:Hide()
		return menu
	end

	function Dropdown.Close()
		if menu then
			menu:Hide()
		end
	end

	function Dropdown.New(parent, width)
		local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
		b:SetSize(width, 22)
		b:SetScript("OnClick", function(self)
			Dropdown.Open(self)
		end)
		return b
	end

	-- options: { { value, label, count (optional) } }
	function Dropdown.Set(b, options, selected, onPick)
		b.options, b.selected, b.onPick = options, selected, onPick
		for _, o in ipairs(options) do
			if o.value == selected then
				b:SetText(o.label .. (o.count and ("  (" .. o.count .. ")") or ""))
			end
		end
	end

	function Dropdown.Open(b)
		local m = Menu()
		if m:IsShown() and m.owner == b then
			m:Hide()
			return
		end
		m.owner = b
		for i, o in ipairs(b.options or {}) do
			local row = m.rows[i]
			if not row then
				row = CreateFrame("Button", nil, m)
				row:SetHeight(18)
				row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
				row.text:SetPoint("LEFT", 8, 0)
				row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
				row.count:SetPoint("RIGHT", -8, 0)
				row:SetHighlightTexture([[Interface\QuestFrame\UI-QuestTitleHighlight]], "ADD")
				m.rows[i] = row
			end
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", m, "TOPLEFT", 3, -4 - (i - 1) * 18)
			row:SetPoint("TOPRIGHT", m, "TOPRIGHT", -3, -4 - (i - 1) * 18)
			row.text:SetText(o.label)
			if o.value == b.selected then
				row.text:SetTextColor(1, 0.82, 0)
			else
				row.text:SetTextColor(1, 1, 1)
			end
			row.count:SetText(o.count and tostring(o.count) or "")
			local grey = o.count == 0 and 0.5 or 1
			row.count:SetTextColor(grey, grey, grey)
			row:SetScript("OnClick", function()
				m:Hide()
				b.onPick(o.value)
			end)
			row:Show()
		end
		for i = #(b.options or {}) + 1, #m.rows do
			m.rows[i]:Hide()
		end
		m:SetSize(max(b:GetWidth(), 190), #(b.options or {}) * 18 + 8)
		m:ClearAllPoints()
		m:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -2)
		catcher:Show()
		m:Show()
	end
end
Eco.Dropdown = Dropdown

-- a chart: textures and lines drawn from a pool, ChartDone hides the rest
function Eco.NewChart(parent)
	local c = CreateFrame("Frame", nil, parent)
	local bg = c:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.3)
	c.bg = bg -- (a theme may colour it)
	c.title = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	c.title:SetPoint("BOTTOMLEFT", c, "TOPLEFT", 0, 3)
	c.high = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	c.high:SetPoint("TOPRIGHT", c, "TOPLEFT", -4, 0)
	c.low = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	c.low:SetPoint("BOTTOMRIGHT", c, "BOTTOMLEFT", -4, 0)
	c.pool, c.lines, c.used, c.usedLines = {}, {}, 0, 0
	return c
end

function Eco.ChartTexture(c, layer)
	c.used = c.used + 1
	local t = c.pool[c.used]
	if not t then
		t = c:CreateTexture(nil, "ARTWORK")
		c.pool[c.used] = t
	end
	t:SetDrawLayer(layer or "ARTWORK")
	t:ClearAllPoints()
	t:Show()
	return t
end

-- a segment between two points (CreateLine), else nothing: the dots stay
function Eco.ChartLine(c, x1, y1, x2, y2, r, g, b)
	if not c.CreateLine then
		return
	end
	c.usedLines = c.usedLines + 1
	local l = c.lines[c.usedLines]
	if not l then
		l = c:CreateLine(nil, "OVERLAY")
		c.lines[c.usedLines] = l
	end
	l:SetThickness(2)
	l:SetColorTexture(r, g, b, 1)
	l:SetStartPoint("BOTTOMLEFT", c, x1, y1)
	l:SetEndPoint("BOTTOMLEFT", c, x2, y2)
	l:Show()
end

function Eco.ChartDone(c)
	for i = c.used + 1, #c.pool do
		c.pool[i]:Hide()
	end
	for i = c.usedLines + 1, #c.lines do
		c.lines[i]:Hide()
	end
	c.used, c.usedLines = 0, 0
end
