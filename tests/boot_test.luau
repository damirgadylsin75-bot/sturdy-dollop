-- Boot smoke test: runs right after the real init.server.luau has executed
-- headless (see harness.mjs --boot). Proves the round actually comes up:
-- planning -> live transition, wave spawning, air support, scoring.
-- NODE_* globals come from the harness fake instance tree.

local Config = require(NODE_config)
local Sim = require(NODE_sim)
local Strikes = require(NODE_strikes)
local Population = require(NODE_population)

-- find the GameState folder: the only instance carrying game attributes
local state
for _, inst in ipairs(ALL_INSTANCES) do
	if inst:GetAttribute("Phase") then
		state = inst
		break
	end
end
assert(state ~= nil, "GameState folder was not created")

local function attr(n)
	return state:GetAttribute(n)
end

-- task.wait stub returns instantly, so the planning countdown ran to zero
-- and startLive() executed during load:
assert(attr("Phase") == "Live", "Phase should be Live after boot, got " .. tostring(attr("Phase")))
assert(attr("CiviliansTotal") == Config.Simulation.Civilians, "civilians must be registered")
assert(attr("PrepBudget") == Config.Prep.Budget, "prep budget must be set")

-- run 3 sim seconds: the t=0 wave must spawn through the spawn queue
__pulse(30 * 3, 1 / 30)
local zombies = attr("ZombiesAlive") or 0
assert(zombies > 0, "wave 1 must have spawned zombies, got " .. zombies)

-- order a missile (start CP = 4 >= cost) and let it land
local ok, err = Strikes.order("missile", 0, 0)
assert(ok, "missile order failed: " .. tostring(err))
__pulse(30 * 3, 1 / 30)

-- run 15 more sim seconds: flow field, movement, infection machinery
__pulse(30 * 15, 1 / 30)
assert(Sim.now() > 18, "sim clock must advance via heartbeats")
assert(Sim.isPaused() == false, "must not be paused")

-- pause freezes the clock
Sim.togglePause()
local t0 = Sim.now()
__pulse(30, 1 / 30)
assert(Sim.now() == t0, "paused heartbeats must not advance sim")
Sim.togglePause()

-- attributes stay coherent
assert(attr("ZombiesAlive") ~= nil, "ZombiesAlive must be published")
assert(attr("CommandPoints") ~= nil, "CommandPoints must be published")

print("boot: phase=" .. attr("Phase") .. " zombies=" .. tostring(attr("ZombiesAlive"))
	.. " saved=" .. tostring(attr("Saved")) .. " simT=" .. math.floor(Sim.now() * 10) / 10)
print("BOOT TEST PASSED")
