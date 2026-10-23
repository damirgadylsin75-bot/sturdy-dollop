-- Headless round simulation (runs under tests/harness.mjs with Roblox stubbed).
-- Exercises: deterministic city generation, defense placement, wave spawning,
-- zombie flow, infection chains, barricades, snipers, airstrike + missile,
-- evacuation, scoring and end-of-round detection.
-- NODE_* globals (the fake instance tree) are provided by the harness.

local Config = require(NODE_config)
local MapGen = require(NODE_mapgen)
local Graph = require(NODE_graph)
local Sim = require(NODE_sim)
local Scoring = require(NODE_scoring)
local Population = require(NODE_population)
local Units = require(NODE_units)
local Strikes = require(NODE_strikes)

local function section(name)
	print("")
	print("== " .. name .. " ==")
end

-- pure logic unit checks ------------------------------------------------------
section("unit checks")

local cityU = MapGen.generate(1)
local d = Graph.dijkstra(cityU, { cityU.evacNode })
assert(d[cityU.evacNode] == 0, "dijkstra: source must be 0")
for id, v in pairs(d) do
	assert(v >= 0, "dijkstra: negative distance")
	if id ~= cityU.evacNode then
		assert(v < math.huge, "dijkstra: grid is fully connected")
	end
end

Sim.bindState(function() end)
assert(Sim.advance(0.05) > 0, "sim clock should advance (0.05s >= fixed step 1/30)")
Sim.togglePause()
assert(Sim.advance(0.05) == 0, "paused clock must not advance")
Sim.togglePause()
assert(Sim.cycleSpeed() == 2 and Sim.cycleSpeed() == 4 and Sim.cycleSpeed() == 1, "speed cycle 1->2->4->1")
Sim.reset()
print("dijkstra + sim clock OK")

-- determinism check ---------------------------------------------------------
section("determinism")
local cityA = MapGen.generate(424242)
local cityB = MapGen.generate(424242)
assert(#cityA.buildings == #cityB.buildings, "building count differs")
assert(#cityA.civSpawns == #cityB.civSpawns, "civ spawn count differs")
assert(cityA.nodes[5].pos.X == cityB.nodes[5].pos.X, "node pos differs")
assert(#cityA.outbreakPoints == 4, "expected 4 outbreak points")
print("seed 424242: buildings=" .. #cityA.buildings .. " civs=" .. #cityA.civSpawns
	.. " edges=" .. #cityA.edges .. " evacNode=" .. tostring(cityA.evacNode))
print("outbreak sectors: " .. cityA.sectorName(cityA.outbreakPoints[1]) .. ", "
	.. cityA.sectorName(cityA.outbreakPoints[2]) .. ", "
	.. cityA.sectorName(cityA.outbreakPoints[3]) .. ", "
	.. cityA.sectorName(cityA.outbreakPoints[4]))

-- wiring --------------------------------------------------------------------
local attrs = {}
local function setAttr(n, v)
	attrs[n] = v
end
local fxCount = 0
local stubRemotes = {
	send = function(payload) fxCount = fxCount + 1 end,
	sendTo = function() end,
}

Sim.bindState(setAttr)
Scoring.boot({ setAttr = setAttr, remotes = stubRemotes, sim = Sim, population = Population, onFinish = function()
	attrs.__finished = true
end })
Strikes.boot({
	remotes = stubRemotes,
	sim = Sim,
	units = Units,
	population = Population,
	scoring = Scoring,
	cityModule = { folders = function() return { marks = Instance.new("Folder") } end },
})
Units.boot({ setAttr = setAttr, remotes = stubRemotes, scoring = Scoring, population = Population })
Population.boot({ cityModule = {}, units = Units, scoring = Scoring, remotes = stubRemotes, setAttr = setAttr })

section("round setup")
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
print("civilians: " .. #city.civSpawns)
assert(attrs.CiviliansTotal == #city.civSpawns, "CiviliansTotal mismatch")
assert(attrs.PrepBudget == Config.Prep.Budget, "budget mismatch")

-- defenses ------------------------------------------------------------------
section("defense placement")
local function tryPlace(tool, x, z)
	if SKIP_DEFENSES then return false end
	local ok, err = Units.place(tool, x, z)
	print(tool .. ": " .. tostring(ok) .. (ok and "" or (" -> " .. tostring(err))))
	return ok, err
end

-- safe zone right on top of the evac pier cluster
local evacPos = city.nodes[city.evacNode].pos
tryPlace("safezone", evacPos.X, evacPos.Y - 40)

-- extra evac a bit north
local extraNode = city.evacNode - 2 * city.n
tryPlace("evac", city.nodes[extraNode].pos.X, city.nodes[extraNode].pos.Y)

-- barricades on edges adjacent to the evac node
local placedBars = 0
for _, e in ipairs(city.edges) do
	if placedBars >= 3 then break end
	if e.a == city.evacNode or e.b == city.evacNode then
		local pa = city.nodes[e.a].pos
		local pb = city.nodes[e.b].pos
		local ok = tryPlace("barricade", (pa.X + pb.X) / 2, (pa.Y + pb.Y) / 2)
		if ok then placedBars = placedBars + 1 end
	end
end

-- snipers on the two buildings closest to the evac
local function distToEvac(b)
	return (b.pos - city.nodes[city.evacNode].pos).Magnitude
end
table.sort(city.buildings, function(a, b)
	return distToEvac(a) < distToEvac(b)
end)
for i = 1, 2 do
	local b = city.buildings[i]
	tryPlace("sniper", b.pos.X, b.pos.Y)
end

-- v0.10: overlapping zones form a fortress wall; third ring touches them
if not SKIP_DEFENSES then
	assert(tryPlace("safezone", 0, 0) == true, "second zone should place")
	assert(tryPlace("safezone", 0, 60) == true, "third overlapping zone should place")
	-- MG teams covering the wall
	assert(tryPlace("mg", evacPos.X + 16, evacPos.Y - 16) == true, "mg should place")
	assert(tryPlace("mg", evacPos.X - 16, evacPos.Y - 16) == true, "mg 2 should place")
end
assert(tryPlace("barricade", 5000, 5000) == false, "far barricade should fail")

-- main loop -----------------------------------------------------------------
section("simulation")
local waves = Config.Simulation.Waves
local orderedAirstrike, orderedMissile = false, false
	local noiseProbed = false
local maxZombies = 0
local dt = 1 / 30

-- wave 1 lands at t=0, before the loop starts
Population.spawnWave(city.outbreakPoints[1], waves[1].count)

for step = 1, 30 * 320 do
	local sdt = Sim.advance(dt)
	local t = Sim.now()
	if sdt > 0 then
		for wi, w in ipairs(waves) do
			if w.t > 0 and math.abs(t - w.t) < dt / 2 then
				Population.spawnWave(city.outbreakPoints[wi], w.count)
			end
		end
		Population.update(sdt)
		Units.update(sdt)

		if t > 100 and not orderedAirstrike then
			orderedAirstrike = true
			local p = city.outbreakPoints[1]
			local ok, err = Strikes.order("airstrike", p.X, p.Y)
			assert(ok, "airstrike order failed: " .. tostring(err))
		end
		if t > 140 and not orderedMissile then
			orderedMissile = true
			local p = city.outbreakPoints[2]
			local ok, err = Strikes.order("missile", p.X, p.Y)
			assert(ok, "missile order failed: " .. tostring(err))
		end
		if t > 150 and not noiseProbed then
			noiseProbed = true
			Population.emitNoise(city.outbreakPoints[3], 150, 5)
		end

		local z = attrs.ZombiesAlive or 0
		if z > maxZombies then maxZombies = z end

		local tInt = math.floor(t + 0.5)
		if tInt % 40 == 0 and math.abs(t - tInt) < dt / 2 then
			local zs, cs = Population.debugSnapshot()
			local st = Population.debugStates()
			print(string.format("t=%3.0f zombies=%3d civs=%3d toEvac=%d converting=%d",
				t, #zs, #cs, st.toEvac or 0, st.converting or 0))
		end
	end
	if attrs.__finished then break end
end

section("results")
print("finished: " .. tostring(attrs.__finished))
print("sim time: " .. math.floor(Sim.now()))
print("saved: " .. tostring(attrs.Saved) .. " / " .. tostring(attrs.CiviliansTotal))
print("lost: " .. tostring(attrs.Lost))
print("kills: " .. tostring(attrs.Kills))
print("max zombies alive: " .. maxZombies)

assert((attrs.Saved or 0) + (attrs.Lost or 0) == attrs.CiviliansTotal or not attrs.__finished,
	"saved+lost should equal total once finished")
assert((attrs.Saved or 0) > 0, "some civilians must be savable (default evac exists)")
assert(maxZombies > 0, "waves must have spawned")
assert(fxCount > 50, "expected fx events (tracers/pings/poofs/explosions)")
if not SKIP_DEFENSES then
	assert((attrs.Kills or 0) > 0, "defenses must kill zombies")
end

print("")
print("ALL SIM TESTS PASSED")
