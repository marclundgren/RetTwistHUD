local ADDON, ns = ...

-- Written out rather than pulled in from LibDBIcon. The addon has no other
-- dependencies and a minimap button is about a hundred lines, so vendoring four
-- library files to get one would cost more than it saves.

local MinimapButton = {}
ns.MinimapButton = MinimapButton

local ORBIT = 80 -- distance from the minimap centre, matches the usual convention
local button

local ICON = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\Logo.tga"

local function UpdatePosition()
	if not button then return end
	local a = math.rad(ns.db.minimap.angle)
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", ORBIT * math.cos(a), ORBIT * math.sin(a))
end

local function OnDragUpdate()
	local mx, my = Minimap:GetCenter()
	if not mx then return end
	local scale = Minimap:GetEffectiveScale()
	local cx, cy = GetCursorPosition()
	ns.db.minimap.angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
	UpdatePosition()
end

function MinimapButton:Build()
	if button or not Minimap then return end

	button = CreateFrame("Button", "RetTwistHUDMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetMovable(true)

	local bg = button:CreateTexture(nil, "BACKGROUND")
	bg:SetSize(20, 20)
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetPoint("TOPLEFT", 7, -5)

	-- The logo is round and carries its own outline on a transparent surround,
	-- so it is drawn whole and centred in the border ring rather than cropped
	-- the way a square spell icon has to be. The ring sits a pixel high.
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetSize(20, 20)
	icon:SetTexture(ICON)
	icon:SetPoint("CENTER", button, "CENTER", 0, 1)
	button.icon = icon

	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetSize(53, 53)
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetPoint("TOPLEFT", 0, 0)

	button:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", OnDragUpdate)
	end)
	button:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
	end)

	button:SetScript("OnClick", function(_, mouseButton)
		if mouseButton == "RightButton" then
			ns.db.locked = not ns.db.locked
			if ns.Ring then ns.Ring:ApplyLock() end
			if ns.Options and ns.Options.Refresh then ns.Options.Refresh() end
			ns.Print(ns.db.locked and "locked." or "unlocked, drag the ring to move it.")
		elseif not (ns.Options and ns.Options:Toggle()) then
			ns.Print("the options window is not available, try /rth help.")
		end
	end)

	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("RetTwistHUD")
		GameTooltip:AddLine("Left click for settings", 0.8, 0.8, 0.8)
		GameTooltip:AddLine("Right click to unlock and move the ring", 0.8, 0.8, 0.8)
		GameTooltip:AddLine("Drag to move this button", 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)

	self:Update()
end

function MinimapButton:Update()
	if not button then return end
	UpdatePosition()
	if ns.db.minimap.hide then button:Hide() else button:Show() end
end
