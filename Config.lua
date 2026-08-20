local ADDON, ns = ...

ns.name = ADDON

-- Palette. Edit these if you want different colours; they are deliberately not
-- exposed through slash commands to keep the option surface small.
-- Values are {r, g, b} in 0..1.
-- Brightness carries the urgent information, hue only labels it. Peripheral
-- vision is close to colourblind, so the twist window is the brightest thing
-- here rather than the greenest.
ns.colors = {
	carrier = { 1.00, 0.76, 0.24 }, -- ring while the carrier seal is up (gold)
	finisher = { 1.00, 0.34, 0.42 }, -- ring while the finisher seal is up (rose)
	other = { 0.62, 0.61, 0.58 }, -- ring while some other seal, or none, is up
	window = { 0.88, 1.00, 0.70 }, -- twist window, twist is available
	blocked = { 0.16, 0.16, 0.15 }, -- global cooldown, and a window it has eaten
	pip = { 1.00, 1.00, 0.98 }, -- the travelling swing marker
	impact = { 1.00, 1.00, 0.98 }, -- the tick at the top of the ring
	lastSafe = { 0.45, 0.72, 1.00 }, -- last point you can start a gcd spell
	judgement = { 0.72, 0.64, 1.00 }, -- judgement cooldown arc
	crusader = { 0.35, 0.88, 0.85 }, -- crusader strike cooldown arc
	sealTime = { 0.88, 0.86, 0.80 }, -- ring around the seal icon, time remaining
}

-- Alpha applied to the part of the ring the swing has not reached yet.
ns.TRAIL_ALPHA = 0.22

local defaults = {
	locked = true,
	radius = 92,
	thickness = 5,
	segments = 90,
	segmentFill = 0.72,
	trackAlpha = 0.7, -- black groove under the ring, the whole contrast story
	trackPad = 2, -- how far the groove sticks out past the ring, in px
	quietAlpha = 0.6, -- overall dim when no twist is pending
	offsetX = 0,
	offsetY = 0,
	windowMs = 400,
	latencyMs = -1, -- -1 means "read it from the client each swing"
	safetyMs = 150, -- window you insist on keeping free when placing lastsafe
	-- The window is already white at full alpha, so it cannot be made brighter.
	-- Extra salience has to come from size instead.
	windowBoost = 1.8, -- how much thicker the window is than the rest of the ring
	showConfirm = true, -- pulse after a swing you twisted in time for
	showGCD = true,
	showPip = true,
	showLastSafe = true,
	showJudgement = true,
	judgementSpan = 55, -- degrees the judgement arc covers when freshly used
	showCrusader = true,
	crusaderSpan = 45, -- deliberately shorter than judgement so the two
	-- silhouettes differ before colour resolves
	crusaderPlacement = "stacked", -- stacked | mirrored | split | nested
	showSeal = true, -- icon of whichever seal is actually up
	showSealDuration = true, -- thin ring around it counting the seal down
	sealIconSize = 26,
	sealAngle = 0, -- degrees clockwise from the top of the ring
	-- always | combat | seal | either | both
	showMode = "either",
	retOnly = true, -- hide the ring outside retribution spec, minimap button stays
	minimap = { angle = 200, hide = false },
	carrierIsCommand = true, -- carrier = Seal of Command, finisher = Seal of Blood
}

ns.SHOW_MODES = {
	always = "always, even standing still",
	combat = "only in combat",
	seal = "only while a tracked seal is up",
	either = "in combat or with a seal up",
	both = "in combat and with a seal up",
}
ns.SHOW_MODE_ORDER = { "always", "combat", "seal", "either", "both" }

ns.CS_PLACEMENTS = {
	stacked = "stacked just outside judgement",
	mirrored = "mirrored on the right side",
	split = "sharing one band with judgement",
	nested = "nested inside the ring",
}
ns.CS_PLACEMENT_ORDER = { "stacked", "mirrored", "split", "nested" }

local function CopyDefaults(src, dst)
	if type(dst) ~= "table" then dst = {} end
	for k, v in pairs(src) do
		if type(v) == "table" then
			dst[k] = CopyDefaults(v, dst[k])
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
	return dst
end

function ns.InitDB()
	RetTwistHUDDB = CopyDefaults(defaults, RetTwistHUDDB)
	ns.db = RetTwistHUDDB

	-- hideOOC was the old single boolean, now folded into showMode.
	if ns.db.hideOOC ~= nil then
		ns.db.showMode = ns.db.hideOOC and "combat" or "always"
		ns.db.hideOOC = nil
	end
	if not ns.SHOW_MODES[ns.db.showMode] then ns.db.showMode = "either" end

	return ns.db
end

-- Wiped in place rather than replaced, because the options panel holds a
-- reference to this table and a new one would leave it editing a ghost.
function ns.ResetDefaults()
	wipe(RetTwistHUDDB)
	ns.InitDB()
	if ns.Ring then
		ns.Ring:Rebuild()
		ns.Ring:ApplyLock()
	end
	if ns.MinimapButton then ns.MinimapButton:Update() end
	if ns.Options and ns.Options.Refresh then ns.Options.Refresh() end
end

local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cffefa027RetTwistHUD|r " .. msg)
end
ns.Print = Print

local function Usage()
	Print("|cffb4b2a9/rth|r on its own opens the options panel. Commands:")
	Print("  |cffb4b2a9/rth lock|r          toggle dragging the ring around")
	Print("  |cffb4b2a9/rth test|r          fake swings so you can position it out of combat")
	Print("  |cffb4b2a9/rth radius|r N      distance from your character, default 92")
	Print("  |cffb4b2a9/rth thickness|r N   ring line weight, default 5")
	Print("  |cffb4b2a9/rth fill|r N        0.2 dotted to 1.0 solid, default 0.72")
	Print("  |cffb4b2a9/rth track|r N      dark groove behind the ring, 0 to 1, default 0.7")
	Print("  |cffb4b2a9/rth trackpad|r N   how far the groove sticks out, default 2")
	Print("  |cffb4b2a9/rth quiet|r N      dim when no twist is pending, default 0.6")
	Print("  |cffb4b2a9/rth window|r N      twist window in ms, default 400")
	Print("  |cffb4b2a9/rth latency|r N     press offset in ms, or 'auto'")
	Print("  |cffb4b2a9/rth safety|r N      window ms to protect from a gcd spell, default 150")
	Print("  |cffb4b2a9/rth boost|r N       twist window thickness, 1 to 3, default 1.8")
	Print("  |cffb4b2a9/rth confirm|r on|off  pulse after a swing you twisted in time for")
	Print("  |cffb4b2a9/rth gcd|r on|off    paint the current global cooldown on the ring")
	Print("  |cffb4b2a9/rth lastsafe|r on|off  mark the last gcd spell you can start")
	Print("  |cffb4b2a9/rth judgement|r on|off arc for the judgement cooldown")
	Print("  |cffb4b2a9/rth crusader|r on|off  arc for the crusader strike cooldown")
	Print("  |cffb4b2a9/rth csplace|r MODE  stacked, mirrored, split, nested")
	Print("  |cffb4b2a9/rth seal|r on|off   icon of the seal you have up")
	Print("  |cffb4b2a9/rth sealduration|r on|off  countdown ring around that icon")
	Print("  |cffb4b2a9/rth sealangle|r N   where it sits, degrees clockwise from top")
	Print("  |cffb4b2a9/rth sealsize|r N    seal icon size, default 26")
	Print("  |cffb4b2a9/rth show|r MODE     always, combat, seal, either, both")
	Print("  |cffb4b2a9/rth ret|r on|off    only show the ring in retribution spec")
	Print("  |cffb4b2a9/rth minimap|r on|off show the minimap button")
	Print("  |cffb4b2a9/rth swap|r          swap which seal is carrier and which is finisher")
	Print("  |cffb4b2a9/rth reset|r         restore every default")
end

local function ToBool(v)
	if v == "on" or v == "1" or v == "true" or v == "yes" then return true end
	if v == "off" or v == "0" or v == "false" or v == "no" then return false end
	return nil
end

local function HandleSlash(input)
	local db = ns.db
	if not db then return end

	local cmd, rest = input:match("^%s*(%S*)%s*(.-)%s*$")
	cmd = (cmd or ""):lower()
	local num = tonumber(rest)

	if cmd == "" or cmd == "options" or cmd == "config" then
		if not (ns.Options and ns.Options:Toggle()) then
			Print("the options window is not available, falling back to commands.")
			Usage()
		end
	elseif cmd == "help" then
		Usage()
	elseif cmd == "lock" then
		db.locked = not db.locked
		ns.Ring:ApplyLock()
		Print(db.locked and "locked." or "unlocked, drag the ring to move it.")
	elseif cmd == "test" then
		ns.ToggleTest()
	elseif cmd == "radius" then
		if num and num >= 30 and num <= 400 then
			db.radius = num
			ns.Ring:Rebuild()
			Print("radius " .. num .. ".")
		else
			Print("radius takes a number between 30 and 400.")
		end
	elseif cmd == "thickness" then
		if num and num >= 1 and num <= 20 then
			db.thickness = num
			ns.Ring:Rebuild()
			Print("thickness " .. num .. ".")
		else
			Print("thickness takes a number between 1 and 20.")
		end
	elseif cmd == "fill" then
		if num and num >= 0.2 and num <= 1 then
			db.segmentFill = num
			ns.Ring:Rebuild()
			Print("segment fill " .. num .. ", 1 is a solid ring and 0.4 is a fine dotted one.")
		else
			Print("fill takes a number between 0.2 and 1.")
		end
	elseif cmd == "track" then
		if num and num >= 0 and num <= 1 then
			db.trackAlpha = num
			ns.Ring:Rebuild()
			Print("dark track behind the ring at " .. num .. ", 0 turns it off.")
		else
			Print("track takes a number between 0 and 1.")
		end
	elseif cmd == "trackpad" then
		if num and num >= 0 and num <= 10 then
			db.trackPad = num
			ns.Ring:Rebuild()
			Print("track sticks out " .. num .. " px past the ring.")
		else
			Print("trackpad takes a number between 0 and 10.")
		end
	elseif cmd == "quiet" then
		if num and num >= 0.1 and num <= 1 then
			db.quietAlpha = num
			Print("dimming to " .. num .. " when no twist is pending.")
		else
			Print("quiet takes a number between 0.1 and 1.")
		end
	elseif cmd == "window" then
		if num and num >= 50 and num <= 1500 then
			db.windowMs = num
			Print("twist window " .. num .. " ms.")
		else
			Print("window takes a number between 50 and 1500 ms.")
		end
	elseif cmd == "latency" then
		if rest:lower() == "auto" then
			db.latencyMs = -1
			Print("latency offset is now read from the client automatically.")
		elseif num and num >= 0 and num <= 1000 then
			db.latencyMs = num
			Print("latency offset " .. num .. " ms.")
		else
			Print("latency takes a number of ms, or 'auto'.")
		end
	elseif cmd == "safety" then
		if num and num >= 0 and num <= 1000 then
			db.safetyMs = num
			Print("protecting the last " .. num .. " ms of the window from a gcd spell.")
		else
			Print("safety takes a number between 0 and 1000 ms.")
		end
	elseif cmd == "boost" then
		if num and num >= 1 and num <= 3 then
			db.windowBoost = num
			Print("twist window drawn " .. num .. " times the ring thickness.")
		else
			Print("boost takes a number between 1 and 3.")
		end
	elseif cmd == "confirm" then
		local b = ToBool(rest:lower())
		if b == nil then Print("confirm takes on or off.") else
			db.showConfirm = b
			Print("twist confirmation pulse " .. (b and "on." or "off."))
		end
	elseif cmd == "gcd" then
		local b = ToBool(rest:lower())
		if b == nil then Print("gcd takes on or off.") else
			db.showGCD = b
			Print("global cooldown display " .. (b and "on." or "off."))
		end
	elseif cmd == "lastsafe" then
		local b = ToBool(rest:lower())
		if b == nil then Print("lastsafe takes on or off.") else
			db.showLastSafe = b
			Print("last safe cast marker " .. (b and "on." or "off."))
		end
	elseif cmd == "judgement" or cmd == "judgment" then
		local b = ToBool(rest:lower())
		if b == nil then Print("judgement takes on or off.") else
			db.showJudgement = b
			ns.Ring:Rebuild()
			Print("judgement arc " .. (b and "on." or "off."))
		end
	elseif cmd == "crusader" or cmd == "cs" then
		local b = ToBool(rest:lower())
		if b == nil then Print("crusader takes on or off.") else
			db.showCrusader = b
			ns.Ring:Rebuild()
			Print("crusader strike arc " .. (b and "on." or "off."))
		end
	elseif cmd == "seal" then
		local b = ToBool(rest:lower())
		if b == nil then Print("seal takes on or off.") else
			db.showSeal = b
			ns.Ring:Rebuild()
			Print("active seal icon " .. (b and "on." or "off."))
		end
	elseif cmd == "sealduration" then
		local b = ToBool(rest:lower())
		if b == nil then Print("sealduration takes on or off.") else
			db.showSealDuration = b
			ns.Ring:Rebuild()
			Print("seal duration ring " .. (b and "on." or "off."))
		end
	elseif cmd == "sealangle" then
		if num and num >= 0 and num <= 359 then
			db.sealAngle = num
			ns.Ring:Rebuild()
			Print("seal icon at " .. num .. " degrees clockwise from the top.")
		else
			Print("sealangle takes a number between 0 and 359, 0 is straight up.")
		end
	elseif cmd == "sealsize" then
		if num and num >= 12 and num <= 64 then
			db.sealIconSize = num
			ns.Ring:Rebuild()
			Print("seal icon " .. num .. " px.")
		else
			Print("sealsize takes a number between 12 and 64.")
		end
	elseif cmd == "csplace" then
		local mode = rest:lower()
		if ns.CS_PLACEMENTS[mode] then
			db.crusaderPlacement = mode
			ns.Ring:Rebuild()
			Print("crusader strike " .. ns.CS_PLACEMENTS[mode] .. ".")
		else
			Print("csplace takes one of: stacked, mirrored, split, nested.")
			for _, k in ipairs(ns.CS_PLACEMENT_ORDER) do
				Print("  |cffb4b2a9" .. k .. "|r  " .. ns.CS_PLACEMENTS[k])
			end
		end
	elseif cmd == "show" then
		local mode = rest:lower()
		if ns.SHOW_MODES[mode] then
			db.showMode = mode
			Print("showing " .. ns.SHOW_MODES[mode] .. ".")
		else
			Print("show takes one of: always, combat, seal, either, both.")
			for k, v in pairs(ns.SHOW_MODES) do
				Print("  |cffb4b2a9" .. k .. "|r  " .. v)
			end
		end
	elseif cmd == "ret" or cmd == "retonly" then
		local b = ToBool(rest:lower())
		if b == nil then Print("ret takes on or off.") else
			db.retOnly = b
			if ns.RefreshSpec then ns.RefreshSpec(true) end
			if b then
				Print("ring limited to retribution spec, currently "
					.. (ns.isRet and "on it." or "off it, so the ring stays hidden."))
			else
				Print("ring shown in every spec.")
			end
		end
	elseif cmd == "swap" then
		db.carrierIsCommand = not db.carrierIsCommand
		ns.ResolveSpells()
		Print("carrier is now " .. tostring(ns.spells.carrierName or "unknown")
			.. ", finisher is " .. tostring(ns.spells.finisherName or "unknown") .. ".")
	elseif cmd == "minimap" then
		local b = ToBool(rest:lower())
		if b == nil then Print("minimap takes on or off.") else
			db.minimap.hide = not b
			ns.MinimapButton:Update()
			Print("minimap button " .. (b and "shown." or "hidden."))
		end
	elseif cmd == "reset" then
		ns.ResetDefaults()
		Print("defaults restored.")
	else
		Usage()
	end
end

SLASH_RETTWISTHUD1 = "/rth"
SLASH_RETTWISTHUD2 = "/rettwisthud"
SlashCmdList["RETTWISTHUD"] = HandleSlash
