local ADDON, ns = ...

-- TBC has no swing timer API. The whole thing is reconstructed from the combat
-- log: a swing landing is also the instant the next swing starts, so every
-- SWING_DAMAGE or SWING_MISSED from us resynchronises the clock exactly.

local Swing = {
	active = false,
	duration = 0,
	expires = 0,
	lastEvent = 0,
}
ns.swing = Swing

-- If no swing event arrives within this long after we expected one, we have
-- stopped attacking (out of range, target dead, moved away) and the ring hides.
local GRACE = 0.55

local playerGUID

function Swing:Reset(now, speed)
	speed = speed or select(1, UnitAttackSpeed("player")) or 0
	if not speed or speed <= 0 then
		self.active = false
		return
	end
	self.duration = speed
	self.expires = now + speed
	self.lastEvent = now
	self.active = true
end

function Swing:Stop()
	self.active = false
end

-- Haste gained or lost mid-swing scales the time left by the same ratio as the
-- weapon speed itself, it does not restart the swing.
function Swing:OnAttackSpeedChanged()
	local speed = select(1, UnitAttackSpeed("player"))
	if not speed or speed <= 0 then return end

	if self.active and self.duration > 0 then
		local now = GetTime()
		local remaining = self.expires - now
		if remaining > 0 then
			self.expires = now + remaining * (speed / self.duration)
		end
	end
	self.duration = speed
end

-- Parry haste: when we parry an incoming attack our own next swing is pulled
-- forward by 40% of the weapon speed, but never closer than 20% of it.
function Swing:ApplyParryHaste()
	if not self.active or self.duration <= 0 then return end
	local now = GetTime()
	local remaining = self.expires - now
	if remaining <= 0 then return end

	local hastened = remaining - 0.4 * self.duration
	local floorAt = 0.2 * self.duration
	if hastened < floorAt then hastened = floorAt end
	if hastened < remaining then
		self.expires = now + hastened
	end
end

function Swing:OnCombatLogEvent()
	local _, sub, _, srcGUID, _, _, _, dstGUID, _, _, _, arg12 = CombatLogGetCurrentEventInfo()

	if sub ~= "SWING_DAMAGE" and sub ~= "SWING_MISSED" then return end

	if srcGUID == playerGUID then
		local now = GetTime()
		-- The instant the swing resolves is the only moment a twist can be
		-- judged, so anything watching gets told before the clock restarts.
		if ns.OnSwingLanded then ns.OnSwingLanded(now) end
		-- Our swing just landed, so the next one starts right now.
		self:Reset(now)
	elseif dstGUID == playerGUID and sub == "SWING_MISSED" and arg12 == "PARRY" then
		self:ApplyParryHaste()
	end
end

-- Called every frame. Returns true while the ring has something to draw.
function Swing:Poll(now)
	if not self.active then return false end
	if now > self.expires + GRACE then
		self.active = false
		return false
	end
	return true
end

-- Progress through the current swing, 0 at the start and 1 at impact.
function Swing:Progress(now)
	if not self.active or self.duration <= 0 then return 0 end
	local p = 1 - (self.expires - now) / self.duration
	if p < 0 then return 0 end
	if p > 1 then return 1 end
	return p
end

function Swing:Init()
	playerGUID = UnitGUID("player")
end
