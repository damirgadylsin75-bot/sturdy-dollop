-- Air support, the improvisation budget.
-- Airstrike: slow, telegraphed, stretched along a street line — prune the
-- horde "with a dotted line" instead of deleting one blob.
-- Cruise missile: near-instant — the answer to clumps forming right now.
-- Both can kill civilians: the city is not on your side.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.config)
local Graph = require(ReplicatedStorage.Shared.graph)

local Strikes = {}

local remotes, sim, units, population, scoring
local city, folders

local marks = {} -- scorch decals, FIFO

local function scorchMark(pos, radius)
	local m = Instance.new("Part")
	m.Shape = Enum.PartType.Cylinder
	m.Anchored = true
	m.CanCollide = false
	m.CanQuery = false
	m.CanTouch = false
	m.CastShadow = false
	m.Material = Enum.Material.SmoothPlastic
	m.Color = Config.color("Scorch")
	m.Transparency = 0.3
	m.Size = Vector3.new(0.3, radius * 1.6, radius * 1.6)
	m.CFrame = CFrame.new(pos.X, 0.5, pos.Y) * CFrame.Angles(0, 0, math.rad(90))
	m.Parent = folders.marks
	marks[#marks + 1] = m
	if #marks > 24 then
		local old = table.remove(marks, 1)
		if old then old:Destroy() end
	end
end

local function impact(pos, radius, big)
	remotes.send({ kind = "explosion", x = pos.X, y = 1.5, z = pos.Y, r = radius, big = big })
	population.killZombiesInRadius(pos, radius)
	population.killCivsInRadius(pos, radius)
	units.damageBarricadesInRadius(pos, radius + 4, 400)
	units.damageZone(pos, radius, big and 320 or 160)
	scorchMark(pos, radius)
	-- the blast rings out: nearby hordes converge on the impact area
	population.emitNoise(pos, big and Config.Simulation.MissileNoiseRadius or Config.Simulation.BlastNoiseRadius, 6)
end

local function orderAirstrike(pos)
	local cfg = Config.Abilities.Airstrike
	-- run direction: along the street nearest to the target
	local _, edge = Graph.nearestEdgePoint(city, pos)
	local dir = Vector2.new(1, 0)
	if edge then
		dir = (city.nodes[edge.b].pos - city.nodes[edge.a].pos).Unit
	end
	local span = (cfg.Bombs - 1) * cfg.BombSpacing
	local first = pos - dir * (span / 2)
	local back = dir * 170
	local p0 = first - back
	local p1 = first + dir * span + back

	remotes.send({
		kind = "bomber",
		from = { x = p0.X, z = p0.Y },
		to = { x = p1.X, z = p1.Y },
		delay = math.max(cfg.Delay - 2, 0.5),
		duration = 4,
	})

	for k = 0, cfg.Bombs - 1 do
		local bp = first + dir * (cfg.BombSpacing * k)
		local t = cfg.Delay + k * cfg.BombInterval
		sim.after(t, function()
			impact(bp, cfg.Radius, false)
		end)
	end
	remotes.send({ kind = "toast", text = "✈ Бомбардировщики в воздухе — удар через " .. cfg.Delay .. " с", tone = "info" })
end

local function orderMissile(pos)
	local cfg = Config.Abilities.Missile
	-- launched from the sea: the battleship at the shore finally earns its keep
	remotes.send({
		kind = "missile",
		to = { x = pos.X, z = pos.Y },
		from = { x = pos.X, y = 80, z = city.waterZ + 340 },
		delay = cfg.Delay,
	})
	sim.after(cfg.Delay, function()
		impact(pos, cfg.Radius, true)
	end)
	remotes.send({ kind = "toast", text = "🚀 Крылатая ракета с линкора — попадание через " .. cfg.Delay .. " с", tone = "info" })
end

function Strikes.boot(deps)
	remotes = deps.remotes
	sim = deps.sim
	units = deps.units
	population = deps.population
	scoring = deps.scoring
	cityModule = deps.cityModule
end

function Strikes.newRound(cityData)
	city = cityData
	folders = cityModule.folders()
end

function Strikes.order(kind, x, z)
	local phasePos = Vector2.new(
		math.clamp(x, -city.half - 100, city.half + 100),
		math.clamp(z, -city.half - 100, city.waterZ + 40)
	)
	if kind == "airstrike" then
		if not scoring.trySpendCP(Config.Costs.Airstrike) then
			return false, "Не хватает командных очков (нужно " .. Config.Costs.Airstrike .. ")"
		end
		orderAirstrike(phasePos)
		return true
	elseif kind == "missile" then
		if not scoring.trySpendCP(Config.Costs.Missile) then
			return false, "Не хватает командных очков (нужно " .. Config.Costs.Missile .. ")"
		end
		orderMissile(phasePos)
		return true
	end
	return false, "Неизвестный удар"
end

return Strikes
