local ADDON, ns = ...

local Options = {}
ns.Options = Options

local refreshers = {}
local widgetCount = 0

local function NextName()
	widgetCount = widgetCount + 1
	return "RetTwistHUDOption" .. widgetCount
end

local function RefreshAll()
	for i = 1, #refreshers do refreshers[i]() end
end
Options.Refresh = RefreshAll

-- Controls are placed against a moving cursor rather than hardcoded offsets, so
-- inserting one does not mean recomputing every y below it.
local function Column(panel, x, y)
	return { panel = panel, x = x, y = y }
end

local function Gap(col, amount)
	col.y = col.y - (amount or 10)
end

local function Header(col, text)
	local fs = col.panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	fs:SetPoint("TOPLEFT", col.panel, "TOPLEFT", col.x, col.y)
	fs:SetText(text)
	col.y = col.y - 24
	return fs
end

-- The label is built by hand rather than read off the template, because which
-- child FontString a check button ships with varies between clients.
local function Check(col, label, get, set)
	local cb = CreateFrame("CheckButton", NextName(), col.panel, "UICheckButtonTemplate")
	cb:SetPoint("TOPLEFT", col.panel, "TOPLEFT", col.x, col.y)
	cb:SetSize(24, 24)

	local fs = col.panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
	fs:SetWidth(158)
	fs:SetJustifyH("LEFT")
	fs:SetText(label)

	cb:SetScript("OnClick", function(self)
		set(self:GetChecked() and true or false)
		RefreshAll()
	end)

	refreshers[#refreshers + 1] = function() cb:SetChecked(get()) end
	col.y = col.y - 26
	return cb
end

local function Slider(col, label, minV, maxV, step, get, set, decimals)
	local name = NextName()
	local s = CreateFrame("Slider", name, col.panel, "OptionsSliderTemplate")
	s:SetPoint("TOPLEFT", col.panel, "TOPLEFT", col.x + 4, col.y - 16)
	s:SetWidth(172)
	s:SetMinMaxValues(minV, maxV)
	s:SetValueStep(step)
	pcall(s.SetObeyStepOnDrag, s, true)

	local low, high, text = _G[name .. "Low"], _G[name .. "High"], _G[name .. "Text"]
	if low then low:SetText("") end
	if high then high:SetText("") end

	local function Describe(v)
		if decimals and decimals > 0 then
			return string.format("%s: %." .. decimals .. "f", label, v)
		end
		return string.format("%s: %d", label, math.floor(v + 0.5))
	end

	local settingSelf = false
	s:SetScript("OnValueChanged", function(_, value)
		if settingSelf then return end
		local snapped = math.floor(value / step + 0.5) * step
		if snapped < minV then snapped = minV end
		if snapped > maxV then snapped = maxV end
		set(snapped)
		if text then text:SetText(Describe(snapped)) end
	end)

	refreshers[#refreshers + 1] = function()
		local v, enabled = get()
		settingSelf = true
		s:SetValue(v)
		settingSelf = false
		if text then text:SetText(Describe(v)) end
		if enabled == false then s:Disable() else s:Enable() end
	end

	col.y = col.y - 40
	return s
end

local function Dropdown(col, label, order, labels, get, set)
	local fs = col.panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	fs:SetPoint("TOPLEFT", col.panel, "TOPLEFT", col.x + 4, col.y)
	fs:SetText(label)

	local dd = CreateFrame("Frame", NextName(), col.panel, "UIDropDownMenuTemplate")
	-- The template carries its own left padding, so it is nudged back to sit
	-- flush with the other controls in the column.
	dd:SetPoint("TOPLEFT", col.panel, "TOPLEFT", col.x - 12, col.y - 16)

	UIDropDownMenu_SetWidth(dd, 145)
	UIDropDownMenu_Initialize(dd, function()
		for i = 1, #order do
			local key = order[i]
			local info = UIDropDownMenu_CreateInfo()
			info.text = labels[key]
			info.value = key
			info.checked = (get() == key)
			info.func = function()
				set(key)
				UIDropDownMenu_SetText(dd, labels[key])
				RefreshAll()
			end
			UIDropDownMenu_AddButton(info)
		end
	end)

	refreshers[#refreshers + 1] = function()
		UIDropDownMenu_SetText(dd, labels[get()] or "")
	end

	col.y = col.y - 52
	return dd
end

local function Button(col, label, onClick)
	local b = CreateFrame("Button", NextName(), col.panel, "UIPanelButtonTemplate")
	b:SetPoint("TOPLEFT", col.panel, "TOPLEFT", col.x + 4, col.y)
	b:SetSize(160, 22)
	b:SetText(label)
	b:SetScript("OnClick", function()
		onClick()
		RefreshAll()
	end)
	col.y = col.y - 28
	return b
end

local function Rebuild()
	if ns.Ring then ns.Ring:Rebuild() end
end

-- A window of our own rather than a page inside Blizzard's options frame. That
-- API has changed shape three times across the Classic re-releases and fails
-- silently when it does, which is exactly what it did here.
local function CreateWindow()
	local panel = CreateFrame("Frame", "RetTwistHUDOptionsPanel", UIParent,
		BackdropTemplateMixin and "BackdropTemplate" or nil)
	panel:SetSize(620, 600)
	panel:SetPoint("CENTER")
	panel:SetFrameStrata("DIALOG")
	panel:SetClampedToScreen(true)
	panel:SetMovable(true)
	panel:EnableMouse(true)
	panel:RegisterForDrag("LeftButton")
	panel:SetScript("OnDragStart", panel.StartMoving)
	panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
	panel:Hide()

	if panel.SetBackdrop then
		panel:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true,
			tileSize = 32,
			edgeSize = 32,
			insets = { left = 11, right = 12, top = 12, bottom = 11 },
		})
	end

	local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -4)

	-- Lets Escape close it, the same as any other dialog.
	tinsert(UISpecialFrames, "RetTwistHUDOptionsPanel")

	return panel
end

function Options:Build()
	if self.panel then return true end

	local db = ns.db
	local panel = CreateWindow()
	panel.name = "RetTwistHUD"
	self.panel = panel

	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", panel, "TOPLEFT", 24, -20)
	title:SetText("RetTwistHUD")

	local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	sub:SetText("Every setting here is also a slash command, see /rth help. Drag this window by its background.")

	local top = -72
	local c1 = Column(panel, 24, top)
	local c2 = Column(panel, 222, top)
	local c3 = Column(panel, 420, top)

	Header(c1, "Shape")
	Slider(c1, "Radius", 30, 400, 1,
		function() return db.radius end,
		function(v) db.radius = v; Rebuild() end)
	Slider(c1, "Thickness", 1, 20, 1,
		function() return db.thickness end,
		function(v) db.thickness = v; Rebuild() end)
	Slider(c1, "Segments", 24, 180, 6,
		function() return db.segments end,
		function(v) db.segments = v; Rebuild() end)
	Slider(c1, "Segment fill", 0.2, 1, 0.02,
		function() return db.segmentFill end,
		function(v) db.segmentFill = v; Rebuild() end, 2)

	Gap(c1, 14)
	Header(c1, "Contrast")
	Slider(c1, "Dark track", 0, 1, 0.05,
		function() return db.trackAlpha end,
		function(v) db.trackAlpha = v; Rebuild() end, 2)
	Slider(c1, "Track padding", 0, 10, 1,
		function() return db.trackPad end,
		function(v) db.trackPad = v; Rebuild() end)
	Slider(c1, "Quiet dim", 0.1, 1, 0.05,
		function() return db.quietAlpha end,
		function(v) db.quietAlpha = v end, 2)

	Gap(c1, 14)
	Header(c1, "Active seal")
	Check(c1, "Show the seal icon",
		function() return db.showSeal end,
		function(v) db.showSeal = v; Rebuild() end)
	Check(c1, "Countdown ring around it",
		function() return db.showSealDuration end,
		function(v) db.showSealDuration = v; Rebuild() end)
	Slider(c1, "Seal position", 0, 359, 5,
		function() return db.sealAngle end,
		function(v) db.sealAngle = v; Rebuild() end)
	Slider(c1, "Seal icon size", 12, 64, 1,
		function() return db.sealIconSize end,
		function(v) db.sealIconSize = v; Rebuild() end)

	Header(c2, "Timing")
	Slider(c2, "Twist window (ms)", 50, 1500, 10,
		function() return db.windowMs end,
		function(v) db.windowMs = v end)
	Check(c2, "Read latency from client",
		function() return db.latencyMs < 0 end,
		function(v) db.latencyMs = v and -1 or 60 end)
	Slider(c2, "Latency offset (ms)", 0, 1000, 5,
		function() return math.max(db.latencyMs, 0), db.latencyMs >= 0 end,
		function(v) db.latencyMs = v end)
	Slider(c2, "Protected window (ms)", 0, 1000, 10,
		function() return db.safetyMs end,
		function(v) db.safetyMs = v end)

	Gap(c2, 14)
	Header(c2, "Elements")
	Check(c2, "Travelling swing pip",
		function() return db.showPip end,
		function(v) db.showPip = v end)
	Check(c2, "Global cooldown arc",
		function() return db.showGCD end,
		function(v) db.showGCD = v end)
	Check(c2, "Last safe cast post",
		function() return db.showLastSafe end,
		function(v) db.showLastSafe = v end)
	Check(c2, "Twist confirmation pulse",
		function() return db.showConfirm end,
		function(v) db.showConfirm = v end)
	Slider(c2, "Twist window thickness", 1, 3, 0.1,
		function() return db.windowBoost end,
		function(v) db.windowBoost = v end, 1)

	Gap(c2, 14)
	Header(c2, "Visibility")
	Dropdown(c2, "Show the ring",
		ns.SHOW_MODE_ORDER, ns.SHOW_MODES,
		function() return db.showMode end,
		function(v) db.showMode = v end)
	Check(c2, "Only in Retribution spec",
		function() return db.retOnly end,
		function(v)
			db.retOnly = v
			if ns.RefreshSpec then ns.RefreshSpec(true) end
		end)

	Header(c3, "Cooldown arcs")
	Check(c3, "Judgement",
		function() return db.showJudgement end,
		function(v) db.showJudgement = v; Rebuild() end)
	Slider(c3, "Judgement span", 10, 90, 5,
		function() return db.judgementSpan end,
		function(v) db.judgementSpan = v; Rebuild() end)
	Check(c3, "Crusader Strike",
		function() return db.showCrusader end,
		function(v) db.showCrusader = v; Rebuild() end)
	Slider(c3, "Crusader Strike span", 10, 90, 5,
		function() return db.crusaderSpan end,
		function(v) db.crusaderSpan = v; Rebuild() end)
	Dropdown(c3, "Crusader Strike placement",
		ns.CS_PLACEMENT_ORDER, ns.CS_PLACEMENTS,
		function() return db.crusaderPlacement end,
		function(v) db.crusaderPlacement = v; Rebuild() end)

	Gap(c3, 14)
	Header(c3, "Behaviour")
	Check(c3, "Seal of Command is carrier",
		function() return db.carrierIsCommand end,
		function(v)
			db.carrierIsCommand = v
			if ns.ResolveSpells then ns.ResolveSpells() end
		end)
	Check(c3, "Show minimap button",
		function() return not db.minimap.hide end,
		function(v)
			db.minimap.hide = not v
			if ns.MinimapButton then ns.MinimapButton:Update() end
		end)
	Check(c3, "Unlock, drag ring to move",
		function() return not db.locked end,
		function(v)
			db.locked = not v
			if ns.Ring then ns.Ring:ApplyLock() end
		end)

	Gap(c3, 8)
	Button(c3, "Preview swings", function()
		if ns.ToggleTest then ns.ToggleTest() end
	end)
	Button(c3, "Restore every default", function()
		if ns.ResetDefaults then ns.ResetDefaults() end
	end)

	panel:SetScript("OnShow", RefreshAll)
	RefreshAll()
	return true
end

function Options:Open()
	if not self.panel then return false end
	RefreshAll()
	self.panel:Show()
	self.panel:Raise()
	return true
end

function Options:Toggle()
	if self.panel and self.panel:IsShown() then
		self.panel:Hide()
		return true
	end
	return self:Open()
end
