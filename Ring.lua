local ADDON, ns = ...

local Ring = {}
ns.Ring = Ring

local TEXTURE = "Interface\\Buttons\\WHITE8X8"
local TAU = math.pi * 2
local PI = math.pi
local sin, cos, max, min, abs, rad, ceil = math.sin, math.cos, math.max, math.min, math.abs, math.rad, math.ceil

-- Older clients do not all support Texture:SetRotation. If it is missing the
-- segments simply stay axis aligned, which at this size still reads as a ring.
local canRotate

local frame, pip, pipBg, tick, tickBg, lastSafe, lastSafeBg, hint
local segments = {}
local track = {}
local judgeSegs = {}
local judgeTrack = {}
local judgeCount = 0
local shownAlpha = 0

local function Paint(tex, r, g, b, a)
	if tex.cr == r and tex.cg == g and tex.cb == b and tex.ca == a then return end
	tex.cr, tex.cg, tex.cb, tex.ca = r, g, b, a
	tex:SetVertexColor(r, g, b, a)
end

local function SealColor()
	local c = ns.colors
	local seal = ns.state.displaySeal or ns.state.seal
	if seal == "carrier" then return c.carrier end
	if seal == "finisher" then return c.finisher end
	return c.other
end

-- A dark backing sized a little larger than whatever sits on top of it. This is
-- the entire reason the ring stays readable over fire, grass or a lit floor.
local function Backing(parent, sublevel)
	local tex = parent:CreateTexture(nil, "BACKGROUND", nil, sublevel or 0)
	tex:SetTexture(TEXTURE)
	return tex
end

function Ring:Create()
	if frame then return end

	frame = CreateFrame("Frame", "RetTwistHUDFrame", UIParent)
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame:SetAlpha(0)
	frame:Hide()

	hint = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
	hint:SetTexture(TEXTURE)
	hint:SetVertexColor(0.94, 0.62, 0.15, 0.10)
	hint:SetAllPoints(frame)
	hint:Hide()

	tickBg = Backing(frame, 2)
	tick = frame:CreateTexture(nil, "OVERLAY")
	tick:SetTexture(TEXTURE)

	lastSafeBg = Backing(frame, 2)
	lastSafeBg:Hide()
	lastSafe = frame:CreateTexture(nil, "OVERLAY")
	lastSafe:SetTexture(TEXTURE)
	lastSafe:Hide()

	pipBg = Backing(frame, 2)
	pip = frame:CreateTexture(nil, "OVERLAY")
	pip:SetTexture(TEXTURE)

	local probe = frame:CreateTexture(nil, "ARTWORK")
	probe:SetTexture(TEXTURE)
	canRotate = pcall(probe.SetRotation, probe, 0)
	probe:Hide()

	frame:SetScript("OnDragStart", function(self)
		if not ns.db.locked then self:StartMoving() end
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local ux, uy = UIParent:GetCenter()
		local fx, fy = self:GetCenter()
		if ux and fx then
			ns.db.offsetX = math.floor(fx - ux + 0.5)
			ns.db.offsetY = math.floor(fy - uy + 0.5)
		end
		Ring:Reposition()
	end)

	self:Rebuild()
	self:ApplyLock()
end

function Ring:Reposition()
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", UIParent, "CENTER", ns.db.offsetX, ns.db.offsetY)
end

function Ring:ApplyLock()
	if not frame then return end
	local locked = ns.db.locked
	-- When locked the ring must be completely transparent to the mouse, or it
	-- would swallow clicks on anything in the middle of the screen.
	frame:EnableMouse(not locked)
	frame:SetMovable(not locked)
	if locked then
		frame:RegisterForDrag()
		hint:Hide()
	else
		frame:RegisterForDrag("LeftButton")
		hint:Show()
		frame:Show()
		frame:SetAlpha(1)
		shownAlpha = 1
	end
end

function Ring:Rebuild()
	if not frame then return end

	local db = ns.db
	local n = db.segments
	local r = db.radius
	local t = db.thickness
	local pad = db.trackPad
	local ta = db.trackAlpha
	local segLen = max(2, (TAU * r / n) * db.segmentFill)
	-- The groove overlaps itself so it reads as one solid dark ring even when
	-- the lit segments on top of it are beads with gaps between them.
	local trackLen = (TAU * r / n) + 1.5

	local span = (r + t * 4.2 + pad * 2) * 2
	frame:SetSize(span, span)
	self:Reposition()

	for i = 1, n do
		local a = (i - 0.5) / n * TAU
		local x, y = r * sin(a), r * cos(a)

		local bg = track[i]
		if not bg then
			bg = Backing(frame, 1)
			track[i] = bg
		end
		bg:SetSize(trackLen, t + pad * 2)
		bg:ClearAllPoints()
		bg:SetPoint("CENTER", frame, "CENTER", x, y)
		if canRotate then bg:SetRotation(-a) end
		bg:SetVertexColor(0, 0, 0, ta)
		if ta > 0 then bg:Show() else bg:Hide() end

		local tex = segments[i]
		if not tex then
			tex = frame:CreateTexture(nil, "ARTWORK")
			tex:SetTexture(TEXTURE)
			segments[i] = tex
		end
		tex:SetSize(segLen, t)
		tex:ClearAllPoints()
		tex:SetPoint("CENTER", frame, "CENTER", x, y)
		if canRotate then tex:SetRotation(-a) end
		tex.cr = nil
		tex:Show()
	end
	for i = n + 1, #segments do
		segments[i]:Hide()
		if track[i] then track[i]:Hide() end
	end

	-- Judgement rides an outer arc centred on the bottom of the ring, well away
	-- from the twist window and the impact tick.
	local jr = r + t * 3.2 + pad
	local spanRad = rad(db.judgementSpan)
	local jn = db.showJudgement and max(6, ceil(2 * spanRad / (TAU / n))) or 0
	local jThick = max(2, t * 0.55)
	local jLen = max(2, (TAU * jr / n) * db.segmentFill)
	local jTrackLen = (TAU * jr / n) + 1.5

	for i = 1, jn do
		local off = ((i - 0.5) / jn) * 2 - 1
		local a = PI + off * spanRad
		local x, y = jr * sin(a), jr * cos(a)

		local bg = judgeTrack[i]
		if not bg then
			bg = Backing(frame, 1)
			judgeTrack[i] = bg
		end
		bg:SetSize(jTrackLen, jThick + pad * 2)
		bg:ClearAllPoints()
		bg:SetPoint("CENTER", frame, "CENTER", x, y)
		if canRotate then bg:SetRotation(-a) end
		bg:SetVertexColor(0, 0, 0, ta)
		bg:Hide()

		local tex = judgeSegs[i]
		if not tex then
			tex = frame:CreateTexture(nil, "ARTWORK")
			tex:SetTexture(TEXTURE)
			judgeSegs[i] = tex
		end
		tex.off = off
		tex:SetSize(jLen, jThick)
		tex:ClearAllPoints()
		tex:SetPoint("CENTER", frame, "CENTER", x, y)
		if canRotate then tex:SetRotation(-a) end
		tex.cr = nil
		tex:Hide()
	end
	for i = jn + 1, #judgeSegs do
		judgeSegs[i]:Hide()
		if judgeTrack[i] then judgeTrack[i]:Hide() end
	end
	judgeCount = jn

	local tickW, tickH = max(2, t * 0.5), t * 3.2
	tick:SetSize(tickW, tickH)
	tick:ClearAllPoints()
	tick:SetPoint("CENTER", frame, "CENTER", 0, r + t * 0.6)
	local c = ns.colors.impact
	tick:SetVertexColor(c[1], c[2], c[3], 1)
	tickBg:SetSize(tickW + pad * 2, tickH + pad * 2)
	tickBg:ClearAllPoints()
	tickBg:SetPoint("CENTER", tick, "CENTER")
	tickBg:SetVertexColor(0, 0, 0, ta)
	if ta > 0 then tickBg:Show() else tickBg:Hide() end

	-- The last safe cast marker crosses the ring like a fence post, which reads
	-- differently from the impact tick sitting outside it.
	local lsW, lsH = max(2, t * 0.5), t * 3.0
	lastSafe:SetSize(lsW, lsH)
	lastSafeBg:SetSize(lsW + pad * 2, lsH + pad * 2)
	lastSafeBg:SetVertexColor(0, 0, 0, ta)

	local pipSize = t * 2.0
	pip:SetSize(pipSize, pipSize)
	pipBg:SetSize(pipSize + pad * 2, pipSize + pad * 2)
	pipBg:SetVertexColor(0, 0, 0, ta)
	if ta > 0 then pipBg:Show() else pipBg:Hide() end
end

function Ring:UpdateJudgement()
	local f = ns.state.judgeFrac
	if not f or judgeCount == 0 then
		for i = 1, judgeCount do
			judgeSegs[i]:Hide()
			judgeTrack[i]:Hide()
		end
		return
	end
	local c = ns.colors.judgement
	local ta = ns.db.trackAlpha
	for i = 1, judgeCount do
		local tex = judgeSegs[i]
		if abs(tex.off) <= f then
			Paint(tex, c[1], c[2], c[3], 0.95)
			tex:Show()
			if ta > 0 then judgeTrack[i]:Show() else judgeTrack[i]:Hide() end
		else
			tex:Hide()
			judgeTrack[i]:Hide()
		end
	end
end

function Ring:Hide(now, dt)
	if shownAlpha <= 0 then return end
	shownAlpha = max(0, shownAlpha - dt * 5)
	frame:SetAlpha(shownAlpha)
	if shownAlpha <= 0 then frame:Hide() end
end

function Ring:Update(now, dt)
	if not frame then return end

	local db = ns.db
	local st = ns.state

	if not st.visible then
		self:Hide(now, dt)
		return
	end

	if not frame:IsShown() then frame:Show() end
	if shownAlpha < 1 then
		shownAlpha = min(1, shownAlpha + dt * 8)
	end

	-- Contrast is a budget. States with no decision in them give theirs back.
	local quiet = (st.idle or st.windowState == "none") and db.quietAlpha or 1
	frame:SetAlpha(shownAlpha * quiet)

	local n = db.segments
	local seal = SealColor()
	local trail = ns.TRAIL_ALPHA

	self:UpdateJudgement()

	-- Not swinging: hold a quiet outline in the seal colour with nothing moving.
	if st.idle then
		for i = 1, n do
			Paint(segments[i], seal[1], seal[2], seal[3], trail)
		end
		pip:Hide()
		pipBg:Hide()
		tick:Hide()
		tickBg:Hide()
		lastSafe:Hide()
		lastSafeBg:Hide()
		return
	end

	local ta = db.trackAlpha
	tick:Show()
	if ta > 0 then tickBg:Show() end

	local p = st.progress
	local colWindow = ns.colors.window
	local colBlocked = ns.colors.blocked

	local wStart, wEnd = st.windowStartP, st.windowEndP
	local windowState = st.windowState
	local gcdP = db.showGCD and st.gcdP or nil
	-- The window is trimmed by the gcd whether or not you have asked to see the
	-- gcd itself, so bright never covers time you cannot actually press in.
	local gcdCut = st.gcdP

	for i = 1, n do
		local tex = segments[i]
		local sp = (i - 0.5) / n
		local r, g, b, a

		if windowState ~= "none" and sp >= wStart and sp <= wEnd then
			if windowState == "open" and not (gcdCut and sp <= gcdCut) then
				r, g, b, a = colWindow[1], colWindow[2], colWindow[3], 1
			else
				r, g, b, a = colBlocked[1], colBlocked[2], colBlocked[3], 0.9
			end
		elseif gcdP and sp > p and sp <= gcdP then
			r, g, b, a = colBlocked[1], colBlocked[2], colBlocked[3], 0.9
		else
			r, g, b = seal[1], seal[2], seal[3]
			a = (sp <= p) and 1 or trail
		end

		Paint(tex, r, g, b, a)
	end

	if st.lastSafeP then
		local a = st.lastSafeP * TAU
		local x, y = db.radius * sin(a), db.radius * cos(a)
		lastSafe:ClearAllPoints()
		lastSafe:SetPoint("CENTER", frame, "CENTER", x, y)
		lastSafeBg:ClearAllPoints()
		lastSafeBg:SetPoint("CENTER", lastSafe, "CENTER")
		if canRotate then
			lastSafe:SetRotation(-a)
			lastSafeBg:SetRotation(-a)
		end
		local c = st.lastSafePassed and colBlocked or ns.colors.lastSafe
		lastSafe:SetVertexColor(c[1], c[2], c[3], st.lastSafePassed and 0.6 or 1)
		lastSafe:Show()
		if ta > 0 then lastSafeBg:Show() else lastSafeBg:Hide() end
	else
		lastSafe:Hide()
		lastSafeBg:Hide()
	end

	if db.showPip then
		local a = p * TAU
		local x, y = db.radius * sin(a), db.radius * cos(a)
		pip:ClearAllPoints()
		pip:SetPoint("CENTER", frame, "CENTER", x, y)
		pipBg:ClearAllPoints()
		pipBg:SetPoint("CENTER", pip, "CENTER")
		local live = windowState == "open" and p >= wStart and p <= wEnd
			and not (gcdCut and p <= gcdCut)
		local c = live and colWindow or ns.colors.pip
		pip:SetVertexColor(c[1], c[2], c[3], 1)
		pip:Show()
		if ta > 0 then pipBg:Show() else pipBg:Hide() end
	else
		pip:Hide()
		pipBg:Hide()
	end
end
