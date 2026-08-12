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

local function Header(parent, text, x, y)
	local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	fs:SetText(text)
	return fs
end

-- The label is built by hand rather than read off the template, because which
-- child FontString a check button ships with varies between clients.
local function Check(parent, label, x, y, get, set)
	local cb = CreateFrame("CheckButton", NextName(), parent, "UICheckButtonTemplate")
	cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	cb:SetWidth(24)
	cb:SetHeight(24)

	local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
	fs:SetText(label)

	cb:SetScript("OnClick", function(self)
		set(self:GetChecked() and true or false)
		RefreshAll()
	end)

	refreshers[#refreshers + 1] = function() cb:SetChecked(get()) end
	return cb
end

local function Slider(parent, label, x, y, minV, maxV, step, get, set, decimals)
	local name = NextName()
	local s = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
	s:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 4, y - 14)
	s:SetWidth(240)
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
	s:SetScript("OnValueChanged", function(self, value)
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
	return s
end

local function Dropdown(parent, label, x, y, order, labels, get, set)
	local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 20, y)
	fs:SetText(label)

	local dd = CreateFrame("Frame", NextName(), parent, "UIDropDownMenuTemplate")
	dd:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 16)

	UIDropDownMenu_SetWidth(dd, 210)
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
	return dd
end

local function Button(parent, label, x, y, onClick)
	local b = CreateFrame("Button", NextName(), parent, "UIPanelButtonTemplate")
	b:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 4, y)
	b:SetWidth(150)
	b:SetHeight(22)
	b:SetText(label)
	b:SetScript("OnClick", function()
		onClick()
		RefreshAll()
	end)
	return b
end

local function Rebuild()
	if ns.Ring then ns.Ring:Rebuild() end
end

local function Register(panel)
	if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
		local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
		category.ID = panel.name
		Settings.RegisterAddOnCategory(category)
		Options.category = category
		return true
	end
	if InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(panel)
		return true
	end
	return false
end

function Options:Build()
	if self.panel then return true end

	local db = ns.db
	local panel = CreateFrame("Frame", "RetTwistHUDOptionsPanel", UIParent)
	panel.name = "RetTwistHUD"
	self.panel = panel

	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
	title:SetText("RetTwistHUD")

	local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	sub:SetText("Swing ring for retribution seal twisting. /rth help for commands.")

	local L, R = 16, 330
	local y = -64

	Header(panel, "Shape", L, y)
	Slider(panel, "Radius", L, y - 20, 30, 400, 1,
		function() return db.radius end,
		function(v) db.radius = v; Rebuild() end)
	Slider(panel, "Thickness", L, y - 62, 1, 20, 1,
		function() return db.thickness end,
		function(v) db.thickness = v; Rebuild() end)
	Slider(panel, "Segment fill", L, y - 104, 0.2, 1, 0.02,
		function() return db.segmentFill end,
		function(v) db.segmentFill = v; Rebuild() end, 2)

	Header(panel, "Contrast", L, y - 152)
	Slider(panel, "Dark track", L, y - 172, 0, 1, 0.05,
		function() return db.trackAlpha end,
		function(v) db.trackAlpha = v; Rebuild() end, 2)
	Slider(panel, "Track padding", L, y - 214, 0, 10, 1,
		function() return db.trackPad end,
		function(v) db.trackPad = v; Rebuild() end)
	Slider(panel, "Quiet dim", L, y - 256, 0.1, 1, 0.05,
		function() return db.quietAlpha end,
		function(v) db.quietAlpha = v end, 2)

	Header(panel, "Timing", L, y - 304)
	Slider(panel, "Twist window (ms)", L, y - 324, 50, 1500, 10,
		function() return db.windowMs end,
		function(v) db.windowMs = v end)
	Check(panel, "Read latency from the client", L, y - 362,
		function() return db.latencyMs < 0 end,
		function(v) db.latencyMs = v and -1 or 60 end)
	Slider(panel, "Latency offset (ms)", L, y - 392, 0, 1000, 5,
		function() return math.max(db.latencyMs, 0), db.latencyMs >= 0 end,
		function(v) db.latencyMs = v end)
	Slider(panel, "Protected window (ms)", L, y - 434, 0, 1000, 10,
		function() return db.safetyMs end,
		function(v) db.safetyMs = v end)

	Header(panel, "Elements", R, y)
	Check(panel, "Travelling swing pip", R, y - 20,
		function() return db.showPip end,
		function(v) db.showPip = v end)
	Check(panel, "Global cooldown on the ring", R, y - 46,
		function() return db.showGCD end,
		function(v) db.showGCD = v end)
	Check(panel, "Last safe cast post", R, y - 72,
		function() return db.showLastSafe end,
		function(v) db.showLastSafe = v end)

	Header(panel, "Cooldown arcs", R, y - 112)
	Check(panel, "Judgement", R, y - 132,
		function() return db.showJudgement end,
		function(v) db.showJudgement = v; Rebuild() end)
	Slider(panel, "Judgement span", R, y - 158, 10, 90, 5,
		function() return db.judgementSpan end,
		function(v) db.judgementSpan = v; Rebuild() end)
	Check(panel, "Crusader Strike", R, y - 200,
		function() return db.showCrusader end,
		function(v) db.showCrusader = v; Rebuild() end)
	Slider(panel, "Crusader Strike span", R, y - 226, 10, 90, 5,
		function() return db.crusaderSpan end,
		function(v) db.crusaderSpan = v; Rebuild() end)
	Dropdown(panel, "Crusader Strike placement", R, y - 268,
		ns.CS_PLACEMENT_ORDER, ns.CS_PLACEMENTS,
		function() return db.crusaderPlacement end,
		function(v) db.crusaderPlacement = v; Rebuild() end)

	Header(panel, "Behaviour", R, y - 320)
	Dropdown(panel, "Show the ring", R, y - 340,
		ns.SHOW_MODE_ORDER, ns.SHOW_MODES,
		function() return db.showMode end,
		function(v) db.showMode = v end)
	Check(panel, "Seal of Command is the carrier", R, y - 392,
		function() return db.carrierIsCommand end,
		function(v)
			db.carrierIsCommand = v
			if ns.ResolveSpells then ns.ResolveSpells() end
		end)
	Check(panel, "Unlock, drag the ring to move it", R, y - 418,
		function() return not db.locked end,
		function(v)
			db.locked = not v
			if ns.Ring then ns.Ring:ApplyLock() end
		end)
	Button(panel, "Preview swings", R, y - 448, function()
		if ns.ToggleTest then ns.ToggleTest() end
	end)

	panel.refresh = RefreshAll
	panel.okay = function() end
	panel.cancel = function() end
	panel:SetScript("OnShow", RefreshAll)

	local registered = Register(panel)
	RefreshAll()
	return registered
end

function Options:Open()
	if not self.panel then return false end

	if Settings and Settings.OpenToCategory and self.category then
		Settings.OpenToCategory(self.category:GetID())
		return true
	end
	if InterfaceOptionsFrame_OpenToCategory then
		-- Called twice on purpose. On these clients the first call reliably
		-- lands on the wrong page.
		InterfaceOptionsFrame_OpenToCategory(self.panel)
		InterfaceOptionsFrame_OpenToCategory(self.panel)
		return true
	end
	return false
end
