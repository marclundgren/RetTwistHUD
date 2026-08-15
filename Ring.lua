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

local frame, brightHost, pip, pipBg, tick, tickBg, lastSafe, lastSafeBg, hint
local sealIcon, sealIconBg
local segments = {}
local track = {}
local pulseSegs = {}
local shownAlpha = 0
-- Segment geometry is worked out in Rebuild but needed again per frame, since
-- the window thickens and thins as the swing moves through it.
local ringSegLen, ringTrackLen = 0, 0

local PULSE_SEGMENTS = 48
local PULSE_TIME = 0.45
local PULSE_GROWTH = 0.35
local pulseUntil = 0

-- Cooldown arcs, keyed to match ns.cooldowns, plus the seal countdown.
local arcs = {
	judgement = { segs = {}, track = {}, count = 0, drain = "center" },
	crusader = { segs = {}, track = {}, count = 0, drain = "center" },
	seal = { segs = {}, track = {}, count = 0, drain = "fromA0" },
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
	local parent = (cfg and cfg.parent) or frame
	local n = 0
	if enabled and cfg and cfg.radius > 0 then
		n = cfg.count or max(4, ceil(abs(cfg.a1 - cfg.a0) / (TAU / db.segments)))
	end

	if n > 0 then
		local thick = cfg.thickness or max(2, db.thickness * 0.55)
		local pad = db.trackPad
		local ta = db.trackAlpha
		local cx, cy = cfg.cx or 0, cfg.cy or 0
		-- Derived from the arc itself rather than the ring, so an arc drawn
		-- around the seal icon spaces its segments correctly too.
		local spacing = cfg.radius * abs(cfg.a1 - cfg.a0) / n
		local segLen = max(2, spacing * db.segmentFill)
		local trackLen = spacing + 1.5

		for i = 1, n do
			local u = (i - 0.5) / n
			local a = cfg.a0 + (cfg.a1 - cfg.a0) * u
			local x, y = cx + cfg.radius * sin(a), cy + cfg.radius * cos(a)

			local bg = arc.track[i]
			if not bg then
				bg = Backing(parent, 1)
				arc.track[i] = bg
			end
			bg:SetSize(trackLen, thick + pad * 2)
			bg:ClearAllPoints()
			bg:SetPoint("CENTER", parent, "CENTER", x, y)
			if canRotate then bg:SetRotation(-a) end
			bg:SetVertexColor(0, 0, 0, ta)
			bg:Hide()

			local tex = arc.segs[i]
			if not tex then
				tex = parent:CreateTexture(nil, "ARTWORK")
				tex:SetTexture(TEXTURE)
				arc.segs[i] = tex
			end
			tex.u = u
			tex:SetSize(segLen, thick)
			tex:ClearAllPoints()
			tex:SetPoint("CENTER", parent, "CENTER", x, y)
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

	-- Anything that stays relevant when the ring goes quiet lives here instead of
	-- on the ring, because child alpha always multiplies the parent's and there
	-- is no way for a child to be brighter than its parent. Currently the seal
	-- readout and the last safe cast post.
	brightHost = CreateFrame("Frame", nil, UIParent)
	brightHost:SetFrameStrata("MEDIUM")
	brightHost:SetFrameLevel(frame:GetFrameLevel() + 2)
	brightHost:SetAlpha(0)
	brightHost:Hide()

	hint = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
	hint:SetTexture(TEXTURE)
	hint:SetVertexColor(0.94, 0.62, 0.15, 0.10)
	hint:SetAllPoints(frame)
	hint:Hide()

	tickBg = Backing(frame, 2)
	tick = frame:CreateTexture(nil, "OVERLAY")
	tick:SetTexture(TEXTURE)

	lastSafeBg = Backing(brightHost, 2)
	lastSafeBg:Hide()
	lastSafe = brightHost:CreateTexture(nil, "OVERLAY")
	lastSafe:SetTexture(TEXTURE)
	lastSafe:Hide()

	pipBg = Backing(frame, 2)
	pip = frame:CreateTexture(nil, "OVERLAY")
	pip:SetTexture(TEXTURE)

	sealIconBg = Backing(brightHost, 2)
	sealIcon = brightHost:CreateTexture(nil, "ARTWORK")
	-- Trims the stock icon border so it reads as art rather than a button.
	sealIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	sealIcon:Hide()
	sealIconBg:Hide()

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
	brightHost:ClearAllPoints()
	brightHost:SetAllPoints(frame)
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
	ringSegLen, ringTrackLen = segLen, trackLen

	local jcfg, ccfg = ArcLayouts(db)

	local iconSize = db.sealIconSize
	local sealR = r + t + pad + iconSize * 0.62 + 4
	local sa = rad(db.sealAngle)
	local sx, sy = sealR * sin(sa), sealR * cos(sa)

	local outer = max(r + t * 2, jcfg.radius, ccfg.radius, sealR + iconSize * 0.8) + t + pad * 2
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
		tex.thick = t
		tex:Show()
	end
	for i = n + 1, #segments do
		segments[i]:Hide()
		if track[i] then track[i]:Hide() end
	end

	-- The confirmation pulse rides the bright layer so it is never dimmed, and
	-- it is repositioned per frame while it plays rather than laid out here.
	local pulseLen = max(2, (TAU * r / PULSE_SEGMENTS) * 0.8)
	for i = 1, PULSE_SEGMENTS do
		local tex = pulseSegs[i]
		if not tex then
			tex = brightHost:CreateTexture(nil, "OVERLAY")
			tex:SetTexture(TEXTURE)
			pulseSegs[i] = tex
		end
		tex:SetSize(pulseLen, max(2, t * 0.8))
		if canRotate then tex:SetRotation(-((i - 0.5) / PULSE_SEGMENTS * TAU)) end
		tex:Hide()
	end

	LayoutArc(arcs.judgement, jcfg, db, db.showJudgement)
	LayoutArc(arcs.crusader, ccfg, db, db.showCrusader)

	sealIcon:SetSize(iconSize, iconSize)
	sealIcon:ClearAllPoints()
	sealIcon:SetPoint("CENTER", brightHost, "CENTER", sx, sy)
	sealIconBg:SetSize(iconSize + pad * 2 + 2, iconSize + pad * 2 + 2)
	sealIconBg:ClearAllPoints()
	sealIconBg:SetPoint("CENTER", sealIcon, "CENTER")
	sealIconBg:SetVertexColor(0, 0, 0, max(ta, 0.5))

	LayoutArc(arcs.seal, {
		parent = brightHost,
		cx = sx,
		cy = sy,
		radius = iconSize * 0.78,
		a0 = 0,
		a1 = TAU,
		drain = "fromA0",
		count = 30,
		thickness = max(2, t * 0.45),
	}, db, db.showSeal and db.showSealDuration)

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

function Ring:Confirm(now)
	if not frame or not ns.db.showConfirm then return end
	pulseUntil = now + PULSE_TIME
end

local function UpdatePulse(now, db)
	if pulseUntil <= now then
		if pulseUntil ~= 0 then
			pulseUntil = 0
			for i = 1, PULSE_SEGMENTS do pulseSegs[i]:Hide() end
		end
		return
	end

	local k = 1 - (pulseUntil - now) / PULSE_TIME
	local radius = db.radius * (1 + PULSE_GROWTH * k)
	local alpha = 1 - k
	local c = ns.colors.window

	for i = 1, PULSE_SEGMENTS do
		local a = (i - 0.5) / PULSE_SEGMENTS * TAU
		local tex = pulseSegs[i]
		tex:ClearAllPoints()
		tex:SetPoint("CENTER", brightHost, "CENTER", radius * sin(a), radius * cos(a))
		tex:SetVertexColor(c[1], c[2], c[3], alpha)
		tex:Show()
	end
end

function Ring:Hide(now, dt)
	if shownAlpha <= 0 then return end
	shownAlpha = max(0, shownAlpha - dt * 5)
	frame:SetAlpha(shownAlpha)
	brightHost:SetAlpha(shownAlpha)
	if shownAlpha <= 0 then
		frame:Hide()
		brightHost:Hide()
	end
end

local function UpdateSeal(db, st, ta)
	if db.showSeal and st.displayIcon then
		sealIcon:SetTexture(st.displayIcon)
		sealIcon:Show()
		if ta > 0 then sealIconBg:Show() else sealIconBg:Hide() end
	else
		sealIcon:Hide()
		sealIconBg:Hide()
	end
	SetArc(arcs.seal, db.showSeal and st.sealFrac or nil, ns.colors.sealTime, ta)
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
	if not brightHost:IsShown() then brightHost:Show() end
	if shownAlpha < 1 then
		shownAlpha = min(1, shownAlpha + dt * 8)
	end

	-- Contrast is a budget. States with no decision in them give theirs back,
	-- but the seal readout is exempt, since which seal is up is exactly what you
	-- want to know when nothing else is happening.
	--
	-- Holding either twist seal counts as having a decision, so this keys on
	-- that rather than on the window being armed. With the finisher up the
	-- window is dark but the post still matters, and dimming it would hide the
	-- one thing worth looking at.
	local quiet = (st.idle or not st.twisting) and db.quietAlpha or 1
	frame:SetAlpha(shownAlpha * quiet)
	brightHost:SetAlpha(shownAlpha)

	local n = db.segments
	local seal = SealColor()
	local trail = ns.TRAIL_ALPHA
	local ta = db.trackAlpha

	SetArc(arcs.judgement, st.judgeFrac, ns.colors.judgement, ta)
	SetArc(arcs.crusader, st.crusaderFrac, ns.colors.crusader, ta)
	UpdateSeal(db, st, ta)
	UpdatePulse(now, db)

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

	local thin = db.thickness
	local fat = max(2, thin * db.windowBoost)

	for i = 1, n do
		local tex = segments[i]
		local sp = (i - 0.5) / n
		local r, g, b, a
		local pressable = false

		if windowState ~= "none" and sp >= wStart and sp <= wEnd then
			if windowState == "open" and not (gcdCut and sp <= gcdCut) then
				r, g, b, a = colWindow[1], colWindow[2], colWindow[3], 1
				pressable = true
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

		-- White at full alpha has nowhere brighter to go, so the window earns its
		-- salience by thickening instead. Only the part you can actually press in
		-- swells, so a window the global cooldown has eaten stays thin.
		local want = pressable and fat or thin
		if tex.thick ~= want then
			tex.thick = want
			tex:SetSize(ringSegLen, want)
			local bg = track[i]
			if bg then bg:SetSize(ringTrackLen, want + db.trackPad * 2) end
		end
	end

	if st.lastSafeP then
		local a = st.lastSafeP * TAU
		local x, y = db.radius * sin(a), db.radius * cos(a)
		lastSafe:ClearAllPoints()
		lastSafe:SetPoint("CENTER", brightHost, "CENTER", x, y)
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
