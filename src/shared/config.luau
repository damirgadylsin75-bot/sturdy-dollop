-- Global tuning for the whole game. Read by both server and client.
-- All balance numbers live here so they are easy to iterate on.

local Config = {}

Config.Version = "0.10.0" -- shown in HUD corner; sync canary for the user

Config.Map = {
	GridSize = 13,        -- intersections per side
	NodeSpacing = 64,     -- studs between intersections
	StreetWidth = 14,
	BuildingChance = 0.72,
	ParkChance = 0.12,
	TowerChance = 0.07,
}

Config.Prep = {
	Duration = 75,        -- real-time seconds of the planning phase
	Budget = 360,         -- prep-phase currency
	MaxBarricades = 16,
	MaxSnipers = 10,
	MaxSafeZones = 8,
	MaxExtraEvacs = 1,
	MaxMg = 6,
	SnapEdgeDist = 50,    -- max click distance from a street (barricades)
	SnapNodeDist = 70,    -- max click distance from an intersection (evac)
}

Config.Costs = {
	Barricade = 10,
	Sniper = 25,
	SafeZone = 30,
	Mg = 35,
	Evac = 20,
	Airstrike = 3,        -- paid with command points
	Missile = 4,
}

Config.Abilities = {
	Airstrike = {
		Delay = 7,          -- sim seconds from order to first bomb
		Bombs = 10,
		BombSpacing = 26,   -- studs between bombs along the run
		BombInterval = 0.22, -- sim seconds between impacts
		Radius = 20,
	},
	Missile = {
		Delay = 1.1,        -- almost instant on purpose
		Radius = 42,
	},
}

Config.CommandPoints = {
	Start = 6,
	Max = 10,
	RegenInterval = 5,    -- sim seconds per +1
}

Config.Simulation = {
	TimeLimit = 480,      -- sim seconds, then results
	Civilians = 190,
	CivWalkSpeed = 6.5,
	CivPanicSpeed = 11.5,
	ZombieSpeed = 10,
	ZombieCap = 1000,
	SpawnBatch = 18,      -- zombies per spawn tick
	SpawnInterval = 0.06, -- sim seconds between spawn ticks
	-- soft crowd separation (no physics): neighbors push each other apart
	Separation = { Radius = 2.4, Factor = 0.32, MaxPush = 0.6, MaxNeighbors = 6 },
	InfectTime = 1.2,     -- seconds of contact to convert a civilian
	InfectRange = 2.6,
	ChaseRange = 12,
	PanicRange = 18,
	PanicMemory = 1.5,
	ThreatRefresh = 1.5,  -- sim seconds between zombie flow-field updates
	WaveTelegraph = 12,   -- seconds of warning before each wave
	AutoEvacFromZone = 2.5, -- sim seconds per civilian saved from a holding zone
	-- sound: explosions/gunfire attract the horde; the bigger the responding
	-- group, the wider zombies smear around the source instead of stacking
	NoiseSpreadBase = 8,
	NoiseSpreadPerZombie = 1.5,
	NoiseSpreadMax = 45,
	SniperNoiseRadius = 60,
	BlastNoiseRadius = 120,
	MissileNoiseRadius = 170,
	CivDetourBudget = 40, -- how far off the evac route a fleeing civilian may detour
	Waves = {
		{ t = 0, count = 160 },
		{ t = 80, count = 210 },
		{ t = 160, count = 270 },
		{ t = 240, count = 360 },
	},
}

Config.Barricade = { Hp = 300, ZombieDps = 14 }
Config.Sniper = { Range = 160, Cooldown = 1.4, HitChance = 0.78 }
Config.SafeZone = { Radius = 42, Hp = 900, ZombieDps = 10 }
-- wall "holds" Hp/ZombieDps zombie-seconds of pressure (900/10 = 90 z-sec)
Config.Mg = {
	Range = 42,
	BurstCd = 0.2,     -- seconds between bursts
	HitChance = 0.5,   -- per burst, vs a single target
	Stagger = 0.45,    -- knockback on hit
	NoiseEvery = 2.5,  -- MG fire attracts the horde periodically
}
Config.Evac = { CaptureRadius = 7 }

Config.Net = {
	StateFolder = "GameState",
	RemotesFolder = "Remotes",
	Command = "Command",
	Event = "Event",
}

Config.Colors = {
	Ground = "20242E",
	Water = "16304F",
	Asphalt = "23262E",
	Sidewalk = "3B414E",
	Curb = "4A5160",
	LaneMark = "B9C2D4",
	Park = "22452E",
	TreeTrunk = "4E3D2B",
	TreeCrown = "2E7444",
	TreeCrownMid = "3C8F54",
	TreeCrownTop = "4FAF6B",
	Building = "343C52",
	BuildingShadow = "10131E",
	Zombie = "3DE070",
	Civilian = "E9F5D2",
	Sniper = "38C8E8",
	Barricade = "E88F1A",
	Mg = "D8C84A",
	Breach = "8A1E1E",
	Evac = "2ECC71",
	SafeZone = "4E86E0",
	Outbreak = "FF2A2A",
	Scorch = "07090F",
}

-- warm rooftop palette (index picked deterministically per building)
Config.RoofColors = { "B4A48A", "A79780", "C2B299", "8F816C", "BBA98F", "9A8C74", "C7B89F" }
Config.RoofTrim = "6E6353"

Config.Interface = {
	CRTEnabled = true, -- client toggle: key C
	-- proximity whitening: the more entities nearby, the closer to white
	-- (gradual; pure client-side, costs nothing on the network)
	DensityGlow = { Radius = 7, Cap = 10, MaxT = 0.8, Interval = 0.12 },
}

local warnedColors = {}
function Config.color(name)
	local hex = Config.Colors[name]
	if not hex then
		-- version skew (stale module) or typo: never crash the render path,
		-- paint an obvious magenta marker instead
		if not warnedColors[name] then
			warnedColors[name] = true
			warn("[config] unknown color key: " .. tostring(name) .. " (stale sync?)")
		end
		return Color3.fromRGB(255, 0, 255)
	end
	return Color3.fromHex(hex)
end

-- Ordered tool definitions for the client toolbar.
function Config.toolInfo()
	return {
		{ id = "safezone",  name = "Зона",      icon = "🛡", key = Enum.KeyCode.One,   cost = Config.Costs.SafeZone,  phase = "Planning" },
		{ id = "barricade", name = "Баррикада", icon = "🚧", key = Enum.KeyCode.Two,   cost = Config.Costs.Barricade, phase = "Planning" },
		{ id = "sniper",    name = "Снайпер",   icon = "🎯", key = Enum.KeyCode.Three, cost = Config.Costs.Sniper,    phase = "Planning" },
		{ id = "evac",      name = "Эвакуация", icon = "⛑", key = Enum.KeyCode.Four,  cost = Config.Costs.Evac,      phase = "Planning" },
		{ id = "mg", name = "Пулемёт", icon = "🔫", key = Enum.KeyCode.Seven, cost = Config.Costs.Mg, phase = "Planning" },
		{ id = "airstrike", name = "Авиаудар",  icon = "✈", key = Enum.KeyCode.Five,  cost = Config.Costs.Airstrike, phase = "Live" },
		{ id = "missile",   name = "Ракета",    icon = "🚀", key = Enum.KeyCode.Six,   cost = Config.Costs.Missile,   phase = "Live" },
	}
end

return Config
