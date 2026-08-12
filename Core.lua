local ADDON, ns = ...

-- Everything the ring draws, recomputed once per frame. Progress values called
-- *P are fractions of the current swing, 0 at its start and 1 at impact.
ns.state = {
	visible = false,
	idle = false, -- visible, but not currently swinging at anything
	progress = 0,
	seal = nil, -- "carrier", "finisher" or nil, from real auras only
	displaySeal = nil, -- what the ring paints, which preview may override
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

local BOOKTYPE = "spell"
local TEST_SPEED = 3.6

-- Candidate ids per seal. Anything that does not resolve on this client is
-- skipped, so the same list works across the Classic re-releases.
local COMMAND_IDS = { 20375 }
local BLOOD_IDS = { 31892, 348700 }
local JUDGEMENT_IDS = { 20271 }
local CRUSADER_IDS = { 35395 }

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
end

local function GetBuffName(index)
	if UnitBuff then return (UnitBuff("player", index)) end
	if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
		local data = C_UnitAuras.GetBuffDataByIndex("player", index)
		return data and data.name
	end
end

local function RefreshSeal()
	local sp = ns.spells
	local seal
	for i = 1, 40 do
		local name = GetBuffName(i)
		if not name then break end
		if name == sp.carrierName then
			seal = "carrier"
			break
		elseif name == sp.finisherName then
			seal = "finisher"
			break
		end
	end
	ns.state.seal = seal
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

	local swinging
	if preview then
		if not sw.active or now >= sw.expires then sw:Reset(now, TEST_SPEED) end
		swinging = true
		st.visible = true
	else
		swinging = sw:Poll(now)
		st.visible = Allowed(db.showMode, UnitAffectingCombat("player"), st.seal ~= nil)
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
	st.lastSafeP = nil
	if db.showLastSafe and st.windowState == "open" then
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

		ns.swing:Init()
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
		ns.swing:OnCombatLogEvent()
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
