local ADDON, ns = ...

local Ring = {}
ns.Ring = Ring

local TEXTURE = "Interface\\Buttons\\WHITE8X8"
local TAU = math.pi * 2
local PI = math.pi
local HALF_PI = math.pi / 2
local sin, cos, max, min, abs, rad, ceil = math.sin, math.cos, math.max, math.min, math.abs, math.rad, math.ceil

-- Older clients do not all support Texture:SetRotation. If it is missing the
-- segments simply stay axis aligned, which at this size still reads as a ring.
local canRotate

local frame, pip, pipBg, tick, tickBg, lastSafe, lastSafeBg, hint
local segments = {}
local track = {}
local shownAlpha = 0

-- Cooldown arcs, keyed to match ns.cooldowns.
local arcs = {
	judgement = { segs = {}, track = {}, count = 0, drain = "center" },
	crusader = { segs = {}, track = {}, count = 0, drain = "center" },
}

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

-- Where each cooldown arc sits. Angles run clockwise from the top of the ring,
-- so PI is the bottom and HALF_PI is the right side.
local function ArcLayouts(db)
	local r, t, pad = db.radius, db.thickness, db.trackPad
	local jr = r + t * 3.2 + pad
	local jSpan = rad(db.judgementSpan)
	local cSpan = rad(db.crusaderSpan)

	local j = { radius = jr, a0 = PI - jSpan, a1 = PI + jSpan, drain = "center" }
	local c

	local place = db.crusaderPlacement
	if place == "mirrored" then
		c = { radius = jr, a0 = HALF_PI - cSpan, a1 = HALF_PI + cSpan, drain = "center" }
	elseif place == "split" then
		-- One band divided at the bottom, each half retracting toward the seam.
		j = { radius = jr, a0 = PI, a1 = PI + jSpan, drain = "fromA0" }
		c = { radius = jr, a0 = PI, a1 = PI - cSpan, drain = "fromA0" }
	elseif place == "nested" then
		c = { radius = r - t * 3.2 - pad, a0 = PI - cSpan, a1 = PI + cSpan, drain = "center" }
	else
		c = { radius = jr + t * 2.4 + pad, a0 = PI - cSpan, a1 = PI + cSpan, drain = "center" }
	end

	return j, c
end

local function LayoutArc(arc, cfg, db, enabled)
	local n = 0
	if enabled and cfg and cfg.radius > 0 then
		n = max(4, ceil(abs(cfg.a1 - cfg.a0) / (TAU / db.segments)))
	end

	if n > 0 then
		local thick = max(2, db.thickness * 0.55)
		local pad = db.trackPad
		local ta = db.trackAlpha
		local spacing = TAU * cfg.radius / db.segments
		local segLen = max(2, spacing * db.segmentFill)
		local trackLen = spacing + 1.5

		for i = 1, n do
			local u = (i - 0.5) / n
			local a = cfg.a0 + (cfg.a1 - cfg.a0) * u
			local x, y = cfg.radius * sin(a), cfg.radius * cos(a)

			local bg = arc.track[i]
			if not bg then
				bg = Backing(frame, 1)
				arc.track[i] = bg
			end
			bg:SetSize(trackLen, thick + pad * 2)
			bg:ClearAllPoints()
			bg:SetPoint("CENTER", frame, "CENTER", x, y)
			if canRotate then bg:SetRotation(-a) end
			bg:SetVertexColor(0, 0, 0, ta)
			bg:Hide()

			local tex = arc.segs[i]
			if not tex then
				tex = frame:CreateTexture(nil, "ARTWORK")
				tex:SetTexture(TEXTURE)
				arc.segs[i] = tex
			end
			tex.u = u
			tex:SetSize(segLen, thick)
			tex:ClearAllPoints()
			tex:SetPoint("CENTER", frame, "CENTER", x, y)
			if canRotate then tex:SetRotation(-a) end
			tex.cr = nil
			tex:Hide()
		end
		arc.drain = cfg.drain
	end

	for i = n + 1, #arc.segs do
		arc.segs[i]:Hide()
		if arc.track[i] then arc.track[i]:Hide() end
	end
	arc.count = n
end

local function SetArc(arc, f, color, ta)
	if not f or arc.count == 0 then
		for i = 1, arc.count do
			arc.segs[i]:Hide()
			arc.track[i]:Hide()
		end
		return
	end
	for i = 1, arc.count do
		local tex = arc.segs[i]
		local lit
		if arc.drain == "center" then
			lit = abs(2 * tex.u - 1) <= f
		else
			lit = tex.u <= f
		end
		if lit then
			Paint(tex, color[1], color[2], color[3], 0.95)
			tex:Show()
			if ta > 0 then arc.track[i]:Show() else arc.track[i]:Hide() end
		else
			tex:Hide()
			arc.track[i]:Hide()
		end
	end
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

	local jcfg, ccfg = ArcLayouts(db)
	local outer = max(r + t * 2, jcfg.radius, ccfg.radius) + t + pad * 2
	frame:SetSize(outer * 2, outer * 2)
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

	LayoutArc(arcs.judgement, jcfg, db, db.showJudgement)
	LayoutArc(arcs.crusader, ccfg, db, db.showCrusader)

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
	local ta = db.trackAlpha

	SetArc(arcs.judgement, st.judgeFrac, ns.colors.judgement, ta)
	SetArc(arcs.crusader, st.crusaderFrac, ns.colors.crusader, ta)

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
