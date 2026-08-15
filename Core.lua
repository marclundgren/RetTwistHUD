local ADDON, ns = ...

-- Everything the ring draws, recomputed once per frame. Progress values called
-- *P are fractions of the current swing, 0 at its start and 1 at impact.
ns.state = {
	visible = false,
	idle = false, -- visible, but not currently swinging at anything
	progress = 0,
	seal = nil, -- twist role: "carrier", "finisher" or nil, from real auras only
	sealKey = nil, -- which seal is actually up, including untwistable ones
	sealIcon = nil,
	sealDuration = 0,
	sealExpires = 0,
	sealFrac = nil, -- seal time remaining, 1 just cast, nil for no seal
	displaySeal = nil, -- what the ring paints, which preview may override
	displayIcon = nil,
	twisting = false, -- either twist seal is up, so this swing has a decision
	windowState = "none", -- "open", "blocked" or "none"
	windowStartP = 0,
	windowEndP = 0,
	gcdP = nil, -- where the current global cooldown ends
	lastSafeP = nil, -- latest point a gcd spell can still be started
	lastSafePassed = false,
	judgeFrac = nil, -- judgement cooldown remaining, 1 just used, nil ready
	crusaderFrac = nil, -- same for crusader strike
}

ns.spells = {}
ns.gcdEnd = 0
ns.gcdLength = 1.5 -- learned from the first real gcd we observe
-- Tracked ability cooldowns, keyed the same way the arcs are.
ns.cooldowns = {
	judgement = { start = 0, duration = 0 },
	crusader = { start = 0, duration = 0 },
}
ns.noMana = false
ns.testing = false
ns.finisherAppliedAt = 0
ns.carrierAppliedAt = 0
local playerGUID

-- Parsed once per event and dispatched, both because the combat log is hot in
-- raids and because the swing and the seal have to be read from one stream.
local function OnCombatLog()
	local _, sub, _, srcGUID, _, _, _, dstGUID, _, _, _, p12, p13 = CombatLogGetCurrentEventInfo()
	local now = GetTime()

	if sub == "SWING_DAMAGE" or sub == "SWING_MISSED" then
		if srcGUID == playerGUID then
			-- Judged before the clock restarts, since the instant the swing
			-- resolves is the only moment a twist can be assessed.
			ns.JudgeTwist(now)
			ns.swing:Reset(now)
		elseif dstGUID == playerGUID and sub == "SWING_MISSED" and p12 == "PARRY" then
			ns.swing:ApplyParryHaste()
		end
		return
	end

	if dstGUID ~= playerGUID then return end
	if sub ~= "SPELL_AURA_APPLIED" and sub ~= "SPELL_AURA_REFRESH" then return end

	-- p12 is the spell id and p13 the name on every SPELL_ prefixed event.
	if p13 == ns.spells.finisherName then
		ns.finisherAppliedAt = now
	elseif p13 == ns.spells.carrierName then
		ns.carrierAppliedAt = now
	end
end

local BOOKTYPE = "spell"
local TEST_SPEED = 3.6

-- Candidate ids per seal. Anything that does not resolve on this client is
-- skipped, so the same list works across the Classic re-releases.
local COMMAND_IDS = { 20375 }
local BLOOD_IDS = { 31892, 348700 }
local JUDGEMENT_IDS = { 20271 }
local CRUSADER_IDS = { 35395 }

-- Every seal, not just the two we twist between. Seal of the Crusader opens
-- boss fights, and treating it as "no seal" made the ring hide itself under the
-- seal-aware visibility modes. Ranks share a name, so one id each is enough.
local SEALS = {
	{ key = "crusader", ids = { 21082 } },
	{ key = "command", ids = { 20375 } },
	{ key = "blood", ids = { 31892, 348700 } },
	{ key = "righteousness", ids = { 21084 } },
	{ key = "justice", ids = { 20164 } },
	{ key = "light", ids = { 20165 } },
	{ key = "wisdom", ids = { 20166 } },
	{ key = "vengeance", ids = { 31801 } },
}

ns.sealsByName = {}

-- These two have C_Spell replacements on newer clients. TBC still has the
-- globals, but falling back costs nothing and stops a nil call from taking the
-- whole addon down if that ever changes under us.
local function SpellCooldown(a, b)
	if GetSpellCooldown then return GetSpellCooldown(a, b) end
	if C_Spell and C_Spell.GetSpellCooldown then
		local info = C_Spell.GetSpellCooldown(a)
		if info then return info.startTime, info.duration, info.isEnabled end
	end
end

local function SpellUsable(name)
	if IsUsableSpell then return IsUsableSpell(name) end
	if C_Spell and C_Spell.IsSpellUsable then return C_Spell.IsSpellUsable(name) end
	return true, false
end

local function FirstKnownName(ids)
	for _, id in ipairs(ids) do
		local name = GetSpellInfo(id)
		if name then return name end
	end
end

-- The spellbook is walked tab by tab and the last match wins, which is always
-- the highest rank we have trained.
local function FindSpellBookSlot(name)
	if not name then return nil end
	local found
	for tab = 1, GetNumSpellTabs() do
		local _, _, offset, numSpells = GetSpellTabInfo(tab)
		if offset and numSpells then
			for i = offset + 1, offset + numSpells do
				if GetSpellBookItemName(i, BOOKTYPE) == name then found = i end
			end
		end
	end
	return found
end

function ns.ResolveSpells()
	local commandName = FirstKnownName(COMMAND_IDS)
	local bloodName = FirstKnownName(BLOOD_IDS)

	local sp = ns.spells
	if ns.db.carrierIsCommand then
		sp.carrierName, sp.finisherName = commandName, bloodName
	else
		sp.carrierName, sp.finisherName = bloodName, commandName
	end
	sp.finisherSlot = FindSpellBookSlot(sp.finisherName)

	sp.judgementName = FirstKnownName(JUDGEMENT_IDS)
	sp.judgementSlot = FindSpellBookSlot(sp.judgementName)
	sp.crusaderName = FirstKnownName(CRUSADER_IDS)
	sp.crusaderSlot = FindSpellBookSlot(sp.crusaderName)

	-- The icon comes from the spell rather than the aura, because which slot
	-- holds the texture in a UnitBuff return has moved between clients.
	wipe(ns.sealsByName)
	for i = 1, #SEALS do
		local seal = SEALS[i]
		for j = 1, #seal.ids do
			local name, _, icon = GetSpellInfo(seal.ids[j])
			if name then
				ns.sealsByName[name] = { key = seal.key, icon = icon }
			end
		end
	end
	sp.carrierIcon = select(3, GetSpellInfo(ns.db.carrierIsCommand and 20375 or 31892))
end

-- Duration and expiry sit at returns 5 and 6 on both the old and the modern
-- UnitBuff signatures, so they can be read without sniffing which one this is.
local function ReadBuff(index)
	if UnitBuff then
		local name, _, _, _, duration, expires = UnitBuff("player", index)
		return name, duration, expires
	end
	if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
		local data = C_UnitAuras.GetBuffDataByIndex("player", index)
		if data then return data.name, data.duration, data.expirationTime end
	end
end

local function RefreshSeal()
	local sp, st = ns.spells, ns.state
	st.seal, st.sealKey, st.sealIcon = nil, nil, nil
	st.sealDuration, st.sealExpires = 0, 0

	for i = 1, 40 do
		local name, duration, expires = ReadBuff(i)
		if not name then break end

		local info = ns.sealsByName[name]
		if info then
			st.sealKey = info.key
			st.sealIcon = info.icon
			st.sealDuration = duration or 0
			st.sealExpires = expires or 0
			-- The twist roles are a subset. Any other seal is still a seal, it
			-- just has no twist pending.
			if name == sp.carrierName then
				st.seal = "carrier"
			elseif name == sp.finisherName then
				st.seal = "finisher"
			end
			break
		end
	end

end

-- What this can actually see is that the finisher seal went up inside the
-- window before the swing resolved, having replaced the carrier, which is to
-- say your press was correctly timed. No combat log event reports that a twist
-- paid out, so this deliberately claims no more than that.
--
-- Both halves are read from the combat log rather than from UNIT_AURA. The
-- client batches UNIT_AURA but delivers the combat log immediately, so judging
-- a twist against aura state lost the race precisely when the timing was
-- tightest, which is the worst possible way for it to fail.
function ns.JudgeTwist(now)
	if not ns.db or not ns.db.showConfirm then return end

	local applied = ns.finisherAppliedAt
	if applied <= 0 then return end

	-- A swap, not a seal cast out of nothing.
	if ns.carrierAppliedAt <= 0 or ns.carrierAppliedAt >= applied then return end

	local delta = now - applied
	-- The margin absorbs the gap between the two events being stamped.
	if delta >= 0 and delta <= (ns.db.windowMs / 1000) + 0.15 then
		ns.Ring:Confirm(now)
	end
end

local function RefreshCooldown()
	local sp = ns.spells
	local start, duration
	if sp.finisherSlot then
		start, duration = SpellCooldown(sp.finisherSlot, BOOKTYPE)
	elseif sp.finisherName then
		start, duration = SpellCooldown(sp.finisherName)
	end
	-- Seals have no cooldown of their own, so anything up to 1.5s is the gcd.
	if start and duration and duration > 0 and duration <= 1.5 then
		ns.gcdEnd = start + duration
		ns.gcdLength = duration
	else
		ns.gcdEnd = 0
	end

	-- Judgement is 8 or 10s and Crusader Strike is 6s, so anything at or under
	-- the gcd length is just the gcd and not a real cooldown worth drawing.
	for key, cd in pairs(ns.cooldowns) do
		local s, d
		local slot, name = sp[key .. "Slot"], sp[key .. "Name"]
		if slot then
			s, d = SpellCooldown(slot, BOOKTYPE)
		elseif name then
			s, d = SpellCooldown(name)
		end
		if s and d and d > 1.5 then
			cd.start, cd.duration = s, d
		else
			cd.start, cd.duration = 0, 0
		end
	end
end

local function RefreshUsable()
	local name = ns.spells.finisherName
	if not name then
		ns.noMana = false
		return
	end
	local _, noMana = SpellUsable(name)
	ns.noMana = noMana and true or false
end

function ns.ToggleTest()
	ns.testing = not ns.testing
	if ns.testing then
		ns.swing:Reset(GetTime(), TEST_SPEED)
		ns.Print("test mode on, showing fake swings. Run /rth test again to stop.")
	else
		ns.swing:Stop()
		ns.Print("test mode off.")
	end
end

local function Latency()
	local db = ns.db
	if db.latencyMs >= 0 then return db.latencyMs / 1000 end
	local lag = select(4, GetNetStats())
	return (lag or 0) / 1000
end

local function Fraction(cd, now)
	if cd.duration <= 0 then return nil end
	local remaining = (cd.start + cd.duration) - now
	if remaining <= 0 then return nil end
	return remaining / cd.duration
end

local function ComputeCooldowns(now, st)
	local db = ns.db
	st.judgeFrac = db.showJudgement and Fraction(ns.cooldowns.judgement, now) or nil
	st.crusaderFrac = db.showCrusader and Fraction(ns.cooldowns.crusader, now) or nil

	st.sealFrac = nil
	if db.showSealDuration and st.sealDuration and st.sealDuration > 0 then
		local remaining = st.sealExpires - now
		if remaining > 0 then
			st.sealFrac = remaining / st.sealDuration
			if st.sealFrac > 1 then st.sealFrac = 1 end
		end
	end
end

local function Allowed(mode, inCombat, hasSeal)
	if mode == "always" then return true end
	if mode == "combat" then return inCombat end
	if mode == "seal" then return hasSeal end
	if mode == "both" then return inCombat and hasSeal end
	return inCombat or hasSeal
end

local function UpdateState(now)
	local st, db, sw = ns.state, ns.db, ns.swing

	-- Unlocking the ring also puts it in preview, otherwise you would be dragging
	-- an invisible frame around whenever you are not mid swing.
	local preview = ns.testing or not db.locked

	ComputeCooldowns(now, st)

	-- Kept apart from st.seal, which only ever reflects real auras, so that
	-- leaving preview cannot strand a fake seal on the ring.
	st.displaySeal = preview and "carrier" or st.seal
	st.displayIcon = st.sealIcon
	if preview and not st.displayIcon then
		st.displayIcon = ns.spells.carrierIcon
		st.sealFrac = st.sealFrac or 0.7
	end

	-- Either twist seal means there is a decision to make this swing. With the
	-- carrier up it is whether to spend a global cooldown on something else,
	-- with the finisher up it is whether you can still swap back in time.
	st.twisting = st.displaySeal == "carrier" or st.displaySeal == "finisher"

	local swinging
	if preview then
		if not sw.active or now >= sw.expires then
			sw:Reset(now, TEST_SPEED)
			-- Pulse on every fake swing, so the confirmation can be checked
			-- without waiting on a real twist to land.
			ns.Ring:Confirm(now)
		end
		swinging = true
		st.visible = true
	else
		swinging = sw:Poll(now)
		-- Any seal counts here, not just the twistable pair.
		st.visible = Allowed(db.showMode, UnitAffectingCombat("player"), st.sealKey ~= nil)
	end

	-- Visible without a swing is a real state: it shows which seal is up while
	-- you are running in, with nothing moving to pull your eye.
	st.idle = not swinging

	if not st.visible or st.idle then
		st.windowState = "none"
		st.gcdP = nil
		st.lastSafeP = nil
		return
	end

	local dur = sw.duration
	if dur <= 0 then
		st.visible = false
		return
	end

	st.progress = sw:Progress(now)

	local lat = Latency()
	local width = db.windowMs / 1000

	-- The server checks the seal at impact, so the press has to leave the client
	-- one round trip earlier. Everything drawn is shifted back by that latency.
	local endP = 1 - lat / dur
	local startP = 1 - (lat + width) / dur
	st.windowEndP = (endP > 1) and 1 or endP
	st.windowStartP = (startP < 0) and 0 or startP

	local gcdEnd = ns.gcdEnd
	st.gcdP = nil
	if gcdEnd > now then
		local gp = 1 - (sw.expires - gcdEnd) / dur
		if gp > 0 then st.gcdP = (gp > 1) and 1 or gp end
	end

	if st.displaySeal ~= "carrier" or (not preview and (ns.noMana or not ns.spells.finisherName)) then
		st.windowState = "none"
	elseif gcdEnd > (sw.expires - lat) - 0.08 then
		-- The global cooldown runs past the point where a press would still
		-- land, so there is nothing to aim at this swing.
		st.windowState = "blocked"
	else
		st.windowState = "open"
	end

	-- The last instant you can start a 1.5s spell and still have the global
	-- cooldown clear with `safetyMs` of the twist window left to press in.
	--
	-- Not gated on which seal is up. The deadline is a property of the swing and
	-- the global cooldown, not of the seal, so it is the same instant whatever
	-- you are holding. Only the cost of passing it changes: a filler ability
	-- with the carrier up, the whole twist with the finisher up, and with any
	-- other seal it is where your setup has to be finished by.
	st.lastSafeP = nil
	if db.showLastSafe then
		local deadline = sw.expires - lat - (db.safetyMs / 1000)
		local lsP = 1 - (sw.expires - (deadline - ns.gcdLength)) / dur
		if lsP > 0 then
			st.lastSafeP = lsP
			st.lastSafePassed = st.progress > lsP
		end
	end
end

local driver = CreateFrame("Frame")
local last = 0

driver:SetScript("OnUpdate", function(_, elapsed)
	local now = GetTime()
	local dt = now - last
	last = now
	if dt <= 0 or dt > 1 then dt = elapsed end
	UpdateState(now)
	ns.Ring:Update(now, dt)
end)
driver:Hide()

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")

events:SetScript("OnEvent", function(self, event, ...)
	if event == "PLAYER_LOGIN" then
		ns.InitDB()

		local _, class = UnitClass("player")
		if class ~= "PALADIN" then
			ns.Print("this character is not a paladin, staying out of the way.")
			return
		end

		playerGUID = UnitGUID("player")
		ns.ResolveSpells()
		ns.Ring:Create()

		-- The panel leans on a lot of Blizzard templates. If any of them differ
		-- on this client it must fail alone, not take the ring down with it.
		local built, err = pcall(ns.Options.Build, ns.Options)
		if not built then
			ns.Print("options panel unavailable, slash commands still work: " .. tostring(err))
		end

		local pinned, mmErr = pcall(ns.MinimapButton.Build, ns.MinimapButton)
		if not pinned then
			ns.Print("minimap button unavailable: " .. tostring(mmErr))
		end

		RefreshSeal()
		RefreshCooldown()
		RefreshUsable()

		self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
		self:RegisterEvent("SPELL_UPDATE_COOLDOWN")
		self:RegisterEvent("SPELL_UPDATE_USABLE")
		self:RegisterEvent("SPELLS_CHANGED")
		self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
		self:RegisterUnitEvent("UNIT_AURA", "player")
		self:RegisterUnitEvent("UNIT_ATTACK_SPEED", "player")

		last = GetTime()
		driver:Show()

		if not ns.spells.finisherName then
			ns.Print("could not find both seals yet. Run /rth swap or relog once you have trained them.")
		end
		return
	end

	if event == "COMBAT_LOG_EVENT_UNFILTERED" then
		OnCombatLog()
	elseif event == "UNIT_ATTACK_SPEED" or event == "PLAYER_EQUIPMENT_CHANGED" then
		ns.swing:OnAttackSpeedChanged()
	elseif event == "UNIT_AURA" then
		RefreshSeal()
	elseif event == "SPELL_UPDATE_COOLDOWN" then
		RefreshCooldown()
	elseif event == "SPELL_UPDATE_USABLE" then
		RefreshUsable()
	elseif event == "SPELLS_CHANGED" then
		ns.ResolveSpells()
		RefreshSeal()
	end
end)
