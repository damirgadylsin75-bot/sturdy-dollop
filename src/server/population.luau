-- Civilians and zombies: street-graph movement, infection, evacuation.
-- Zombies are a FLOW, not a squad: they follow a distance field toward the
-- nearest living humans, so geometry (barricades, zones) shapes the horde.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.config)
local Graph = require(ReplicatedStorage.Shared.graph)

local Population = {}

local cityModule, units, scoring, remotes, setAttr

local city, folders
local civs, zoms = {}, {}
local nextCivId, nextZomId = 0, 0
local live = false
local simNow = 0

local distEvac = {}   -- field: distance to the nearest evacuation node
local evacPoints = {} -- { { nodeId, pos } }
local threat = {}     -- field: distance to the nearest living human
local threatTimer = 0

local spawnQueue = {}
local spawnAccum = 0
local attrTimer = 0
local telegraphs = {} -- { pos, part }

local CELL = 40
local civGrid, zomGrid = {}, {}

-- forward declarations ----------------------------------------------------
local convertCivilian, saveCivilian, killZombie, killCivilian

-- helpers -----------------------------------------------------------------

local function makeDot(folder, colorName, size)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = Vector3.new(size, size, size)
	p.Color = Config.color(colorName)
	p.Parent = folder
	return p
end

local function placeDot(dot, pos)
	dot.CFrame = CFrame.new(pos.X, 1.4, pos.Y)
end

local function gridKey(x, z)
	return math.floor(x / CELL) .. ":" .. math.floor(z / CELL)
end

local function rebuildGrid(grid, container)
	local fresh = {}
	for _, e in pairs(container) do
		local k = gridKey(e.pos.X, e.pos.Y)
		local cell = fresh[k]
		if not cell then
			cell = {}
			fresh[k] = cell
		end
		cell[#cell + 1] = e
	end
	return fresh
end

local function findNearestInGrid(grid, pos, radius)
	local r = math.ceil(radius / CELL)
	local cx = math.floor(pos.X / CELL)
	local cz = math.floor(pos.Y / CELL)
	local best, bestD = nil, radius * radius
	for gx = cx - r, cx + r do
		for gz = cz - r, cz + r do
			local cell = grid[gx .. ":" .. gz]
			if cell then
				for _, e in ipairs(cell) do
					local d = (e.pos - pos).SquaredMagnitude
					if d < bestD then
						best, bestD = e, d
					end
				end
			end
		end
	end
	return best, math.sqrt(bestD)
end

-- fields ------------------------------------------------------------------

local function recomputeEvacField()
	local sources = {}
	for _, e in ipairs(evacPoints) do
		sources[#sources + 1] = e.nodeId
	end
	if #sources == 0 then return end
	distEvac = Graph.dijkstra(city, sources)
end

local function recomputeThreat()
	local sources = {}
	local seen = {}
	for _, c in pairs(civs) do
		local nid = Graph.nearestNode(city, c.pos)
		if not seen[nid] then
			seen[nid] = true
			sources[#sources + 1] = nid
		end
	end
	if #sources == 0 then
		threat = {}
		return
	end
	threat = Graph.dijkstra(city, sources, function(edge)
		local len = (city.nodes[edge.a].pos - city.nodes[edge.b].pos).Magnitude
		if units.barricadeOnEdge(edge.key) then
			return len * 6 -- go around if you can; break through if you must
		end
		return len
	end)
end

-- movement ----------------------------------------------------------------

local function nextNodeByField(fromNode, toNode, field)
	local node = city.nodes[toNode]
	local best, bestVal = nil, math.huge
	for _, nb in ipairs(node.edges) do
		local skipBack = nb == fromNode and #node.edges > 1
		if not skipBack then
			local v = field[nb] or math.huge
			if v < bestVal - 1e-6 then
				best, bestVal = nb, v
			elseif best and math.abs(v - bestVal) <= 1e-6 and math.random() < 0.34 then
				best = nb -- tie-break randomly so hordes don't march in lockstep
			end
		end
	end
	if best then return best end
	return fromNode -- dead end: turn back
end

local function arrived(agent)
	agent.from = agent.to
	agent.to = nextNodeByField(agent.from, agent.from, agent.zombie and threat or distEvac)
end

local function moveAlongEdge(agent, dt, speed)
	local fromPos = city.nodes[agent.from].pos
	local toPos = city.nodes[agent.to].pos
	local delta = toPos - agent.pos
	local dist = delta.Magnitude
	if dist < 1e-4 then
		arrived(agent)
		return
	end
	local dir = delta / dist
	local step = speed * dt

	if agent.zombie and units then
		local bar = units.barricadeOnEdge(Graph.edgeKey(agent.from, agent.to))
		if bar then
			local barDist = bar.sFromA
			if agent.from ~= bar.edge.a then
				barDist = bar.edgeLen - bar.sFromA
			end
			local stopAt = barDist - 1.8
			local s = (agent.pos - fromPos):Dot(dir)
			if s < stopAt then
				local m = math.min(step, stopAt - s)
				agent.pos = agent.pos + dir * m
				if stopAt - s <= step then
					agent.attackBar = bar
				end
				return
			end
		end
	end

	local m = math.min(step, dist)
	agent.pos = agent.pos + dir * m
	if m >= dist - 1e-4 then
		arrived(agent)
	end
end

-- civilians ---------------------------------------------------------------

local function spawnCivilian(pos)
	nextCivId = nextCivId + 1
	local c = {
		id = nextCivId,
		pos = pos,
		from = Graph.nearestNode(city, pos),
		state = "idle",
		speedMul = 0.85 + math.random() * 0.3,
	}
	c.to = c.from
	c.dot = makeDot(folders.civs, "Civilian", 2.2)
	placeDot(c.dot, pos)
	civs[c.id] = c
end

function saveCivilian(c)
	if not civs[c.id] then return end
	civs[c.id] = nil
	c.dot:Destroy()
	scoring.bump("Saved", 1)
	if remotes then
		remotes.send({ kind = "savedPing", x = c.pos.X, z = c.pos.Y })
	end
end

function killCivilian(c, cause)
	if not civs[c.id] then return end
	civs[c.id] = nil
	c.dot:Destroy()
	scoring.bump("Lost", 1)
	if remotes then
		remotes.send({ kind = "poof", x = c.pos.X, z = c.pos.Y, tone = "civilian" })
	end
end

function convertCivilian(c)
	if not civs[c.id] then return end
	civs[c.id] = nil
	scoring.bump("Lost", 1)
	-- the dot itself becomes a zombie: infection made visible
	local dot = c.dot
	dot.Color = Config.color("Zombie")
	dot.Size = Vector3.new(2.6, 2.6, 2.6)
	dot.Parent = folders.zoms
	local from = Graph.nearestNode(city, c.pos)
	local z = {
		id = (function() nextZomId = nextZomId + 1 return nextZomId end)(),
		pos = c.pos,
		from = from,
		to = from,
		zombie = true,
		speedMul = 0.85 + math.random() * 0.35,
		dot = dot,
	}
	z.to = nextNodeByField(z.from, z.from, threat)
	zoms[z.id] = z
	if remotes then
		remotes.send({ kind = "poof", x = c.pos.X, z = c.pos.Y, tone = "convert" })
	end
end

local function updateCiv(c, dt)
	if c.convert then
		-- being devoured: frozen in place; the progress lives here so it
		-- survives the chewer dying, and rolls back if no zombie remains
		local z = findNearestInGrid(zomGrid, c.pos, Config.Simulation.InfectRange + 1)
		if z then
			c.convert = c.convert + dt
			if c.convert >= Config.Simulation.InfectTime then
				convertCivilian(c)
			end
		else
			c.convert = c.convert - dt
			if c.convert <= 0 then
				c.convert = nil
			end
		end
		return
	end
	if c.state ~= "toEvac" then
		return
	end
	local speed = Config.Simulation.CivWalkSpeed
	c.panicScan = (c.panicScan or math.random() * 0.35) - dt
	if c.panicScan <= 0 then
		c.panicScan = 0.35
		local z = findNearestInGrid(zomGrid, c.pos, Config.Simulation.PanicRange)
		if z then
			c.panicUntil = simNow + Config.Simulation.PanicMemory
		end
	end
	if c.panicUntil and c.panicUntil > simNow then
		speed = Config.Simulation.CivPanicSpeed
	end
	moveAlongEdge(c, dt, speed * c.speedMul)
	for _, e in ipairs(evacPoints) do
		if (c.pos - e.pos).Magnitude < Config.Evac.CaptureRadius then
			saveCivilian(c)
			return
		end
	end
end

-- zombies -----------------------------------------------------------------

local function registerZombie(pos, dot)
	nextZomId = nextZomId + 1
	local z = {
		id = nextZomId,
		pos = pos,
		from = Graph.nearestNode(city, pos),
		zombie = true,
		speedMul = 0.85 + math.random() * 0.35,
	}
	z.to = z.from
	if dot then
		z.dot = dot
	else
		z.dot = makeDot(folders.zoms, "Zombie", 2.6)
		placeDot(z.dot, pos)
	end
	z.to = nextNodeByField(z.from, z.from, threat)
	zoms[z.id] = z
	return z
end

function killZombie(z, cause)
	if not zoms[z.id] then return end
	zoms[z.id] = nil
	z.dot:Destroy()
	if cause == "sniper" or cause == "blast" then
		scoring.bump("Kills", 1)
		if remotes then
			remotes.send({ kind = "poof", x = z.pos.X, z = z.pos.Y, tone = "zombie" })
		end
	end
end

local function updateZombie(z, dt)
	-- chewing through a barricade
	if z.attackBar then
		if z.attackBar.dead then
			z.attackBar = nil
		else
			units.damageBarricade(z.attackBar, Config.Barricade.ZombieDps * dt)
			return
		end
	end
	-- direct chase of a spotted civilian
	local target = z.chaseTarget
	if target then
		if not civs[target.id] then
			z.chaseTarget = nil
		else
			local delta = target.pos - z.pos
			local d = delta.Magnitude
			if d > Config.Simulation.ChaseRange * 1.8 then
				z.chaseTarget = nil
			else
				if d > 1e-4 then
					local step = math.min(Config.Simulation.ZombieSpeed * z.speedMul * dt, d)
					z.pos = z.pos + (delta / d) * step
				end
				-- latching on starts the devouring; the progress itself is
				-- tracked on the civilian side so it survives chewer deaths
				if d < Config.Simulation.InfectRange then
					target.convert = target.convert or 0
				end
				return
			end
		end
	end
	z.scan = (z.scan or math.random() * 0.25) - dt
	if z.scan <= 0 then
		z.scan = 0.25
		local c = findNearestInGrid(civGrid, z.pos, Config.Simulation.ChaseRange)
		if c and not c.convert then
			z.chaseTarget = c
		end
	end
	if z.chaseTarget then return end
	moveAlongEdge(z, dt, Config.Simulation.ZombieSpeed * z.speedMul)
end

-- public API --------------------------------------------------------------

-- exposed for Units (snipers)
Population.killZombie = killZombie

function Population.boot(deps)
	cityModule = deps.cityModule
	units = deps.units
	scoring = deps.scoring
	remotes = deps.remotes
	setAttr = deps.setAttr
end

function Population.newRound(cityData, folderTbl)
	city = cityData
	folders = folderTbl
	civs, zoms = {}, {}
	nextCivId, nextZomId = 0, 0
	live = false
	simNow = 0
	distEvac = {}
	evacPoints = {}
	threat = {}
	threatTimer = 0
	spawnQueue = {}
	spawnAccum = 0
	telegraphs = {}
	for _, pos in ipairs(cityData.civSpawns) do
		spawnCivilian(pos)
	end
	recomputeThreat()
	setAttr("ZombiesAlive", 0)
end

function Population.addEvacPoint(nodeId)
	for _, e in ipairs(evacPoints) do
		if e.nodeId == nodeId then return end
	end
	evacPoints[#evacPoints + 1] = { nodeId = nodeId, pos = city.nodes[nodeId].pos }
	recomputeEvacField()
end

-- persistent (true) rings survive the planning phase until the wave lands;
-- combat-time rings pulse as a countdown for incoming waves.
function Population.showTelegraph(point, persistent)
	for i = #telegraphs, 1, -1 do
		local t = telegraphs[i]
		if (t.pos - point).Magnitude < 2 then
			t.part:Destroy()
			table.remove(telegraphs, i)
		end
	end
	local r = 30
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Color = Config.color("Outbreak")
	ring.Size = Vector3.new(0.8, r * 2, r * 2)
	ring.CFrame = CFrame.new(point.X, 0.9, point.Y) * CFrame.Angles(0, 0, math.rad(90))
	ring.Transparency = 0.25
	ring.Parent = folders.units
	local tween = game:GetService("TweenService"):Create(
		ring,
		TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Transparency = 0.8 }
	)
	tween:Play()
	telegraphs[#telegraphs + 1] = { pos = point, part = ring }
end

local function destroyTelegraph(point)
	for i = #telegraphs, 1, -1 do
		local t = telegraphs[i]
		if (t.pos - point).Magnitude < 2 then
			t.part:Destroy()
			table.remove(telegraphs, i)
		end
	end
end

function Population.spawnWave(point, count)
	destroyTelegraph(point)
	local base, edge = Graph.nearestEdgePoint(city, point)
	local dir = (city.nodes[edge.b].pos - city.nodes[edge.a].pos).Unit
	local room = math.min(count * 1.2, 46)
	for _ = 1, count do
		if #zoms >= Config.Simulation.ZombieCap then break end
		local t = (math.random() - 0.5) * room
		spawnQueue[#spawnQueue + 1] = base + dir * t
	end
end

function Population.beginSim()
	live = true
	simNow = 0
	for _, c in pairs(civs) do
		c.from = Graph.nearestNode(city, c.pos)
		c.to = c.from
		if units.isSheltered(c.pos) then
			c.state = "sheltered"
		else
			c.state = "toEvac"
			c.to = nextNodeByField(c.from, c.from, distEvac)
		end
	end
	recomputeThreat()
end

function Population.panicSheltered()
	for _, c in pairs(civs) do
		if c.state == "sheltered" then
			c.state = "toEvac"
			c.from = Graph.nearestNode(city, c.pos)
			c.to = nextNodeByField(c.from, c.from, distEvac)
		end
	end
end

function Population.saveSheltered(center, radius)
	local candidates = {}
	for _, c in pairs(civs) do
		if c.state == "sheltered" and (c.pos - center).Magnitude <= radius + 6 then
			candidates[#candidates + 1] = c
		end
	end
	if #candidates > 0 then
		saveCivilian(candidates[math.random(#candidates)])
	end
end

function Population.killZombiesInRadius(pos, radius)
	local doomed = {}
	for _, z in pairs(zoms) do
		if (z.pos - pos).Magnitude <= radius then
			doomed[#doomed + 1] = z
		end
	end
	for _, z in ipairs(doomed) do
		killZombie(z, "blast")
	end
	return #doomed
end

function Population.killCivsInRadius(pos, radius)
	local doomed = {}
	for _, c in pairs(civs) do
		if (c.pos - pos).Magnitude <= radius then
			doomed[#doomed + 1] = c
		end
	end
	for _, c in ipairs(doomed) do
		killCivilian(c, "blast")
	end
	return #doomed
end

function Population.nearestZombie(pos, radius)
	return findNearestInGrid(zomGrid, pos, radius)
end

function Population.countZombiesNear(pos, radius)
	local n = 0
	for _, z in pairs(zoms) do
		if (z.pos - pos).Magnitude <= radius then
			n = n + 1
		end
	end
	return n
end

-- diagnostic hook for the headless test harness
function Population.debugSnapshot()
	local zs, cs = {}, {}
	for _, z in pairs(zoms) do
		zs[#zs + 1] = z.pos
	end
	for _, c in pairs(civs) do
		cs[#cs + 1] = c.pos
	end
	return zs, cs
end

function Population.debugStates()
	local counts = { toEvac = 0, sheltered = 0, idle = 0, converting = 0 }
	for _, c in pairs(civs) do
		if c.convert then
			counts.converting = counts.converting + 1
		elseif c.state then
			counts[c.state] = (counts[c.state] or 0) + 1
		end
	end
	return counts
end

function Population.update(dt)
	if not live then return end
	simNow = simNow + dt

	civGrid = rebuildGrid(civGrid, civs)
	zomGrid = rebuildGrid(zomGrid, zoms)

	threatTimer = threatTimer - dt
	if threatTimer <= 0 then
		threatTimer = Config.Simulation.ThreatRefresh
		recomputeThreat()
	end

	if #spawnQueue > 0 then
		spawnAccum = spawnAccum - dt
		if spawnAccum <= 0 then
			spawnAccum = 0.1
			local batch = math.min(5, #spawnQueue)
			for _ = 1, batch do
				local spot = table.remove(spawnQueue)
				registerZombie(spot, nil)
			end
			setAttr("ZombiesAlive", 0) -- refreshed below anyway
		end
	end

	for _, z in pairs(zoms) do
		updateZombie(z, dt)
	end
	for _, c in pairs(civs) do
		updateCiv(c, dt)
	end
	for _, z in pairs(zoms) do
		placeDot(z.dot, z.pos)
	end
	for _, c in pairs(civs) do
		placeDot(c.dot, c.pos)
	end

	attrTimer = attrTimer - dt
	if attrTimer <= 0 then
		attrTimer = 0.5
		local n = 0
		for _ in pairs(zoms) do n = n + 1 end
		setAttr("ZombiesAlive", n)
	end
end

return Population
