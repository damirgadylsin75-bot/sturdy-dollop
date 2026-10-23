-- Runs headlessly on a REAL Roblox server via Open Cloud Luau Execution.
-- Builds a full round from the actual place DataModel (requires the real
-- ModuleScripts from the rojo build), simulates it, returns a summary.
-- The `return` value arrives in the task's `results`; prints land in `logs`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.config)
local MapGen = require(ReplicatedStorage.Shared.mapgen)
local Sim = require(ServerScriptService.Game.sim)
local Scoring = require(ServerScriptService.Game.scoring)
local Population = require(ServerScriptService.Game.population)
local Units = require(ServerScriptService.Game.units)
local Strikes = require(ServerScriptService.Game.strikes)

local setAttrs = {}
local function setAttr(n, v)
	setAttrs[n] = v
end
local stubRemotes = { send = function() end, sendTo = function() end }

Sim.bindState(setAttr)
Scoring.boot({ setAttr = setAttr, remotes = stubRemotes, sim = Sim, population = Population, onFinish = function()
	setAttrs.__finished = true
end })
Strikes.boot({ remotes = stubRemotes, sim = Sim, units = Units, population = Population, scoring = Scoring,
	cityModule = require(ServerScriptService.Game.city) })
Units.boot({ setAttr = setAttr, remotes = stubRemotes, scoring = Scoring, population = Population })
Population.boot({ cityModule = require(ServerScriptService.Game.city), units = Units, scoring = Scoring,
	remotes = stubRemotes, setAttr = setAttr })

local city = MapGen.generate(987654)
local folders = {
	city = Instance.new("Folder"),
	civs = Instance.new("Folder"),
	zoms = Instance.new("Folder"),
	units = Instance.new("Folder"),
	marks = Instance.new("Folder"),
}
Units.newRound(city, folders)
Population.newRound(city, folders)
Strikes.newRound(city)
Scoring.newRound(#city.civSpawns)
Units.addDefaultEvac(city.evacNode)
Population.beginSim()
Scoring.startWatch()

-- place a small defense like the headless suite does
local evacPos = city.nodes[city.evacNode].pos
Units.place("safezone", evacPos.X, evacPos.Y - 40)

-- wave 1 at t=0
Population.spawnWave(city.outbreakPoints[1], Config.Simulation.Waves[1].count)

local maxZombies = 0
local orderedStrike = false
local dt = 1 / 30
for step = 1, 30 * 200 do
	local sdt = Sim.advance(dt)
	local t = Sim.now()
	if sdt > 0 then
		for wi, w in ipairs(Config.Simulation.Waves) do
			if w.t > 0 and math.abs(t - w.t) < dt / 2 then
				Population.spawnWave(city.outbreakPoints[wi], w.count)
			end
		end
		Population.update(sdt)
		Units.update(sdt)
		if t > 100 and not orderedStrike then
			orderedStrike = true
			Strikes.order("airstrike", city.outbreakPoints[1].X, city.outbreakPoints[1].Y)
		end
		if (setAttrs.ZombiesAlive or 0) > maxZombies then
			maxZombies = setAttrs.ZombiesAlive
		end
	end
	if setAttrs.__finished then break end
end

local saved, lost = setAttrs.Saved or 0, setAttrs.Lost or 0
assert(saved + lost == #city.civSpawns or not setAttrs.__finished, "civilians must be accounted for")
assert(saved > 0, "default evac must save someone on a real engine too")
assert(maxZombies > 0, "waves must spawn on a real engine")

print(("cloud smoke: saved=%d lost=%d kills=%s maxZombies=%d version=%s"):format(
	saved, lost, tostring(setAttrs.Kills), maxZombies, tostring(Config.Version)))

return {
	ok = true,
	version = Config.Version,
	saved = saved,
	lost = lost,
	kills = setAttrs.Kills,
	maxZombies = maxZombies,
	finished = setAttrs.__finished == true,
}
