-- Global tuning for the whole game. Read by both server and client.
-- All balance numbers live here so they are easy to iterate on.

local Config = {}

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
	Budget = 140,         -- prep-phase currency
	MaxBarricades = 12,
	MaxSnipers = 8,
	MaxSafeZones = 1,
	MaxExtraEvacs = 1,
	SnapEdgeDist = 50,    -- max click distance from a street (barricades)
	SnapNodeDist = 70,    -- max click distance from an intersection (evac)
}

Config.Costs = {
	Barricade = 10,
	Sniper = 25,
	SafeZone = 30,
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
	Start = 4,
	Max = 10,
	RegenInterval = 5,    -- sim seconds per +1
}

Config.Simulation = {
	TimeLimit = 480,      -- sim seconds, then results
	Civilians = 140,
	CivWalkSpeed = 6.5,
	CivPanicSpeed = 11.5,
	ZombieSpeed = 10,
	ZombieCap = 260,
	InfectTime = 1.2,     -- seconds of contact to convert a civilian
	InfectRange = 2.6,
	ChaseRange = 12,
	PanicRange = 18,
	PanicMemory = 1.5,
	ThreatRefresh = 1.5,  -- sim seconds between zombie flow-field updates
	WaveTelegraph = 12,   -- seconds of warning before each wave
	AutoEvacFromZone = 2.5, -- sim seconds per civilian saved from a holding zone
	Waves = {
		{ t = 0, count = 26 },
		{ t = 80, count = 32 },
		{ t = 160, count = 45 },
		{ t = 240, count = 55 },
	},
}

Config.Barricade = { Hp = 300, ZombieDps = 14 }
Config.Sniper = { Range = 160, Cooldown = 1.4, HitChance = 0.78 }
Config.SafeZone = { Radius = 42, Hp = 600, ZombieDps = 16 }
Config.Evac = { CaptureRadius = 7 }

Config.Net = {
	StateFolder = "GameState",
	RemotesFolder = "Remotes",
	Command = "Command",
	Event = "Event",
}

Config.Colors = {
	Ground = "1C2333",
	Water = "1D3A5F",
	Street = "343D52",
	Park = "24512F",
	Building = "49546E",
	Zombie = "FF4747",
	Civilian = "FFD166",
	Sniper = "35D0FF",
	Barricade = "FF9F1C",
	Evac = "2ECC71",
	SafeZone = "5B8CFF",
	Outbreak = "FF2A2A",
	Scorch = "0B0D12",
}

function Config.color(name)
	return Color3.fromHex(Config.Colors[name])
end

-- Ordered tool definitions for the client toolbar.
function Config.toolInfo()
	return {
		{ id = "safezone",  name = "Зона",      icon = "🛡", key = Enum.KeyCode.One,   cost = Config.Costs.SafeZone,  phase = "Planning" },
		{ id = "barricade", name = "Баррикада", icon = "🚧", key = Enum.KeyCode.Two,   cost = Config.Costs.Barricade, phase = "Planning" },
		{ id = "sniper",    name = "Снайпер",   icon = "🎯", key = Enum.KeyCode.Three, cost = Config.Costs.Sniper,    phase = "Planning" },
		{ id = "evac",      name = "Эвакуация", icon = "⛑", key = Enum.KeyCode.Four,  cost = Config.Costs.Evac,      phase = "Planning" },
		{ id = "airstrike", name = "Авиаудар",  icon = "✈", key = Enum.KeyCode.Five,  cost = Config.Costs.Airstrike, phase = "Live" },
		{ id = "missile",   name = "Ракета",    icon = "🚀", key = Enum.KeyCode.Six,   cost = Config.Costs.Missile,   phase = "Live" },
	}
end

return Config
