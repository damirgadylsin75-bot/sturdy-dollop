-- Player-placed units: barricades, rooftop snipers, the safe zone and
-- extra evacuation points. All of them are PLANNING-phase tools: once the
-- simulation starts, the player can only improvise with air support.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.config)
local Graph = require(ReplicatedStorage.Shared.graph)

local Units = {}

local setAttr, remotes, scoring, population
local city, folders

local barricades = {}      -- array of records
local barricadeByEdge = {} -- [edgeKey] = record
local snipers = {}
local zones = {}           -- safe zone records (union walls when overlapping)
local mgs = {}             -- machine-gun teams
local extraEvacs = 0

local rayParams

-- helpers -----------------------------------------------------------------

local function part(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = true
	p.CanTouch = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		p[k] = v
	end
	p.Parent = parent
	return p
end

local function publishCounts()
	setAttr("Barricades", #barricades)
	setAttr("Snipers", #snipers)
	setAttr("SafeZones", #zones)
	setAttr("EvacExtra", extraEvacs)
	setAttr("Mgs", #mgs)
end

local function buildBeacon(pos)
	part({
		Name = "EvacDisc",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5, Config.Evac.CaptureRadius * 2, Config.Evac.CaptureRadius * 2),
		CFrame = CFrame.new(pos.X, 0.7, pos.Y) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Config.color("Evac"),
		CastShadow = false,
	}, folders.units).Transparency = 0.3
	part({
		Name = "EvacBeam",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(34, 3, 3),
		CFrame = CFrame.new(pos.X, 17.5, pos.Y) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Config.color("Evac"),
		CastShadow = false,
	}, folders.units).Transparency = 0.55
end

-- placement ---------------------------------------------------------------

local function placeBarricade(x, z)
	local point, edge, dist = Graph.nearestEdgePoint(city, Vector2.new(x, z))
	if dist > Config.Prep.SnapEdgeDist then
		return false, "Щёлкни рядом с улицей"
	end
	if barricadeByEdge[edge.key] then
		return false, "На этой улице уже есть баррикада"
	end
	if not scoring.trySpendPrep(Config.Costs.Barricade) then
		return false, "Не хватает бюджета подготовки"
	end

	local a = city.nodes[edge.a].pos
	local b = city.nodes[edge.b].pos
	local dir = (b - a).Unit
	local sFromA = (point - a):Dot(dir)
	local yaw = math.atan2(dir.X, dir.Y) -- local X ends up across the street
	local p = part({
		Name = "Barricade",
		Size = Vector3.new(Config.Map.StreetWidth + 6, 3.2, 2.4),
		CFrame = CFrame.new(point.X, 1.8, point.Y) * CFrame.Angles(0, yaw, 0),
		Color = Config.color("Barricade"),
	}, folders.units)

	local rec = {
		key = edge.key,
		edge = edge,
		edgeLen = (b - a).Magnitude,
		sFromA = sFromA,
		pos = point,
		hp = Config.Barricade.Hp,
		maxHp = Config.Barricade.Hp,
		part = p,
		flash = 0,
		dead = false,
	}
	barricades[#barricades + 1] = rec
	barricadeByEdge[edge.key] = rec
	publishCounts()
	return true
end

local function buildingAt(x, z)
	for _, b in ipairs(city.buildings) do
		if math.abs(x - b.pos.X) <= b.size.X / 2 + 2 and math.abs(z - b.pos.Y) <= b.size.Y / 2 + 2 then
			return b
		end
	end
	return nil
end

local function placeSniper(x, z)
	local b = buildingAt(x, z)
	if not b then
		return false, "Снайперов ставят на крыши домов"
	end
	if not scoring.trySpendPrep(Config.Costs.Sniper) then
		return false, "Не хватает бюджета подготовки"
	end

	local rx = math.clamp(x, b.pos.X - b.size.X / 2 + 2, b.pos.X + b.size.X / 2 - 2)
	local rz = math.clamp(z, b.pos.Y - b.size.Y / 2 + 2, b.pos.Y + b.size.Y / 2 - 2)
	local roofY = b.height + 1.6
	part({
		Name = "Sniper",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(3.2, 3.2, 3.2),
		CFrame = CFrame.new(rx, roofY, rz),
		Color = Config.color("Sniper"),
		CastShadow = false,
		Material = Enum.Material.Neon,
	}, folders.units)

	snipers[#snipers + 1] = {
		pos = Vector3.new(rx, roofY, rz),
		cd = math.random() * 0.5,
	}
	publishCounts()
	return true
end

local function placeSafeZone(x, z)
	local r = Config.SafeZone.Radius
	if z > city.waterZ - r - 6 then
		return false, "Зона не влезает — слишком близко к воде"
	end
	if not scoring.trySpendPrep(Config.Costs.SafeZone) then
		return false, "Не хватает бюджета подготовки"
	end

	local ring = part({
		Name = "ZoneRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.55, r * 2 + 4, r * 2 + 4),
		CFrame = CFrame.new(x, 0.75, z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Config.color("Evac"),
		CastShadow = false,
	}, folders.units)
	ring.Transparency = 0.25
	local disc = part({
		Name = "ZoneDisc",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, r * 2 - 2, r * 2 - 2),
		CFrame = CFrame.new(x, 0.6, z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Config.color("SafeZone"),
		CastShadow = false,
	}, folders.units)
	disc.Transparency = 0.8

	zones[#zones + 1] = {
		center = Vector2.new(x, z),
		radius = r,
		hp = Config.SafeZone.Hp,
		maxHp = Config.SafeZone.Hp,
		ring = ring,
		disc = disc,
		-- stagger save pulses so multiple zones don't tick in sync
		saveTimer = Config.Simulation.AutoEvacFromZone + 0.4 * #zones,
		breached = false,
	}
	publishCounts()
	return true
end

local function placeEvac(x, z)
	local nodeId = Graph.nearestNodeWithin(city, Vector2.new(x, z), Config.Prep.SnapNodeDist)
	if not nodeId then
		return false, "Эвакуацию ставят у перекрёстка"
	end
	if not scoring.trySpendPrep(Config.Costs.Evac) then
		return false, "Не хватает бюджета подготовки"
	end
	buildBeacon(city.nodes[nodeId].pos)
	population.addEvacPoint(nodeId)
	extraEvacs = extraEvacs + 1
	publishCounts()
	return true
end

local function placeMg(x, z)
	if not scoring.trySpendPrep(Config.Costs.Mg) then
		return false, "Не хватает бюджета подготовки"
	end
	part({
		Name = "MgTeam",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(3, 3, 3),
		CFrame = CFrame.new(x, 1.6, z),
		Color = Config.color("Mg"),
		CastShadow = false,
		Material = Enum.Material.Neon,
	}, folders.units)
	mgs[#mgs + 1] = {
		pos = Vector3.new(x, 1.6, z),
		cd = math.random() * Config.Mg.BurstCd,
		noiseT = Config.Mg.NoiseEvery * math.random(),
	}
	publishCounts()
	return true
end

function Units.place(tool, x, z)
	if math.abs(x) > city.half + 250 or z > city.waterZ + 50 or z < -city.half - 250 then
		return false, "Слишком далеко от города"
	end
	if tool == "barricade" then
		if #barricades >= Config.Prep.MaxBarricades then
			return false, "Достигнут лимит баррикад"
		end
		return placeBarricade(x, z)
	elseif tool == "sniper" then
		if #snipers >= Config.Prep.MaxSnipers then
			return false, "Достигнут лимит снайперов"
		end
		return placeSniper(x, z)
	elseif tool == "safezone" then
		if #zones >= Config.Prep.MaxSafeZones then
			return false, "Достигнут лимит безопасных зон (" .. Config.Prep.MaxSafeZones .. ")"
		end
		return placeSafeZone(x, z)
	elseif tool == "mg" then
		if #mgs >= Config.Prep.MaxMg then
			return false, "Достигнут лимит пулемётчиков (" .. Config.Prep.MaxMg .. ")"
		end
		return placeMg(x, z)
	elseif tool == "evac" then
		if extraEvacs >= Config.Prep.MaxExtraEvacs then
			return false, "Дополнительная эвакуация уже есть"
		end
		return placeEvac(x, z)
	end
	return false, "Неизвестный инструмент"
end

-- combat behavior ---------------------------------------------------------

function Units.barricadeOnEdge(key)
	return barricadeByEdge[key]
end

function Units.damageBarricade(bar, dmg)
	if bar.dead then return end
	bar.hp = bar.hp - dmg
	bar.flash = (bar.flash or 0) - dmg
	if bar.hp <= 0 then
		bar.dead = true
		bar.part:Destroy()
		barricadeByEdge[bar.key] = nil
		remotes.send({ kind = "barBreak", x = bar.pos.X, z = bar.pos.Y })
	else
		if bar.flash <= 0 then
			bar.flash = 40
			local f = 1 - bar.hp / bar.maxHp
			bar.part.Color = Config.color("Barricade"):Lerp(Color3.new(0.1, 0.08, 0.05), f * 0.8)
		end
	end
end

function Units.damageBarricadesInRadius(pos, radius, dmg)
	for _, bar in ipairs(barricades) do
		if not bar.dead and (bar.pos - pos).Magnitude <= radius then
			Units.damageBarricade(bar, dmg)
		end
	end
end

function Units.damageZone(pos, radius, dmg)
	for _, zn in ipairs(zones) do
		if not zn.breached then
			local closest = Vector2.new(
				math.clamp(pos.X, zn.center.X - zn.radius, zn.center.X + zn.radius),
				math.clamp(pos.Y, zn.center.Y - zn.radius, zn.center.Y + zn.radius)
			)
			if (closest - pos).Magnitude <= radius then
				zn.hp = zn.hp - dmg
			end
		end
	end
end

local function breachZone(zn)
	if zn.breached then return end
	zn.breached = true
	zn.ring.Color = Config.color("Outbreak")
	zn.disc.Color = Config.color("Outbreak")
	zn.disc.Transparency = 0.92
	-- visible hole where the crowd broke through
	local dir = zn.pressDir or Vector2.new(1, 0)
	local holePos = zn.center + dir * zn.radius
	part({
		Name = "BreachHole",
		Size = Vector3.new(9, 1.1, 9),
		CFrame = CFrame.new(holePos.X, 0.55, holePos.Y),
		Color = Config.color("Breach"),
		CastShadow = false,
	}, folders.units).Transparency = 0.15
	remotes.send({ kind = "barBreak", x = holePos.X, z = holePos.Y })
	remotes.send({ kind = "announce", text = "❌ Стену зоны продавила орда — там дыра!", dur = 3.5 })
	population.panicSheltered()
end

-- zombies pressing on a wall: wall hp drains, pressure direction accumulates
function Units.pressZone(zn, dirUnit, dmg)
	if zn.breached then return end
	zn.hp = zn.hp - dmg
	zn.pressDir = (zn.pressDir or Vector2.new(0, 0)) + dirUnit * dmg
	if zn.hp <= 0 then
		breachZone(zn)
	end
end

-- blocks a zombie from walking into an intact zone; clamps to the wall and
-- registers pressure. fromPos outside + toPos inside => stopped at rim.
function Units.blockZoneEntry(fromPos, toPos, dt)
	for _, zn in ipairs(zones) do
		if not zn.breached then
			local dFrom = (fromPos - zn.center).Magnitude
			if dFrom > zn.radius then
				local toCenter = toPos - zn.center
				if toCenter.Magnitude < zn.radius then
					local dirUnit = toCenter.Unit
					local stopped = zn.center + dirUnit * (zn.radius + 0.4)
					Units.pressZone(zn, dirUnit, Config.SafeZone.ZombieDps * dt)
					return stopped
				end
			end
		end
	end
	return nil
end

local function sectorLabel(pos)
	return ""
end

function Units.isSheltered(pos)
	for _, zn in ipairs(zones) do
		if not zn.breached and (pos - zn.center).Magnitude <= zn.radius then
			return true
		end
	end
	return false
end

function Units.getZones()
	local alive = {}
	for _, zn in ipairs(zones) do
		if not zn.breached then
			alive[#alive + 1] = zn
		end
	end
	return alive
end

local function updateSnipers(dt)
	for _, s in ipairs(snipers) do
		s.cd = s.cd - dt
		if s.cd <= 0 then
			s.cd = Config.Sniper.Cooldown
			local z = population.nearestZombie(Vector2.new(s.pos.X, s.pos.Z), Config.Sniper.Range)
			if z then
				local target = Vector3.new(z.pos.X, 1.4, z.pos.Y)
				local hit = workspace:Raycast(s.pos, target - s.pos, rayParams)
				local blocked = hit ~= nil and (hit.Position - target).Magnitude > 4
				if not blocked then
					remotes.send({
						kind = "tracer",
						from = { x = s.pos.X, y = s.pos.Y, z = s.pos.Z },
						to = { x = target.X, y = target.Y, z = target.Z },
					})
					if math.random() < Config.Sniper.HitChance then
						population.killZombie(z, "sniper")
					end
					-- gunshot echoes: the horde slowly drifts toward active rifles
					population.emitNoise(Vector2.new(s.pos.X, s.pos.Z), Config.Simulation.SniperNoiseRadius, 3)
				end
			end
		end
	end
end

local function updateZone(dt)
	for _, zn in ipairs(zones) do
		if not zn.breached then
			local pressured = population.countZombiesNear(zn.center, zn.radius + 4)
			if pressured > 0 then
				zn.hp = zn.hp - pressured * Config.SafeZone.ZombieDps * dt
				if zn.hp <= 0 then
					breachZone(zn)
				else
					zn.ring.Color = Config.color("Evac"):Lerp(Config.color("Outbreak"), 1 - zn.hp / zn.maxHp)
				end
			end
			if not zn.breached then
				zn.saveTimer = zn.saveTimer - dt
				if zn.saveTimer <= 0 then
					zn.saveTimer = Config.Simulation.AutoEvacFromZone
					population.saveSheltered(zn.center, zn.radius)
				end
			end
		end
	end
end

-- lifecycle ---------------------------------------------------------------

function Units.boot(deps)
	setAttr = deps.setAttr
	remotes = deps.remotes
	scoring = deps.scoring
	population = deps.population
end

function Units.newRound(cityData, folderTbl)
	city = cityData
	folders = folderTbl
	barricades = {}
	barricadeByEdge = {}
	snipers = {}
	zones = {}
	mgs = {}
	extraEvacs = 0
	rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { folders.civs, folders.zoms, folders.units, folders.marks }
	publishCounts()
end

function Units.addDefaultEvac(nodeId)
	buildBeacon(city.nodes[nodeId].pos)
	population.addEvacPoint(nodeId)
end

local function updateMgs(dt)
	for _, mg in ipairs(mgs) do
		mg.cd = mg.cd - dt
		if mg.cd <= 0 then
			mg.cd = Config.Mg.BurstCd
			local z = population.nearestZombie(Vector2.new(mg.pos.X, mg.pos.Z), Config.Mg.Range)
			if z then
				local target = Vector3.new(z.pos.X, 1.4, z.pos.Y)
				remotes.send({
					kind = "tracer",
					from = { x = mg.pos.X, y = mg.pos.Y, z = mg.pos.Z },
					to = { x = target.X, y = target.Y, z = target.Z },
				})
				if math.random() < Config.Mg.HitChance then
					-- stagger: push the target back a step, then damage
					local pushDir = Vector2.new(z.pos.X - mg.pos.X, z.pos.Y - mg.pos.Z)
					if pushDir.Magnitude > 0.01 then
						z.pos = z.pos + pushDir.Unit * Config.Mg.Stagger
					end
					z.hp = (z.hp or 1) - 0.5
					if z.hp <= 0 then
						population.killZombie(z, "mg")
					end
				end
				mg.noiseT = mg.noiseT - Config.Mg.BurstCd
				if mg.noiseT <= 0 then
					mg.noiseT = Config.Mg.NoiseEvery
					population.emitNoise(Vector2.new(mg.pos.X, mg.pos.Z), Config.Simulation.SniperNoiseRadius, 2)
				end
			end
		end
	end
end

function Units.update(dt)
	updateSnipers(dt)
	updateMgs(dt)
	updateZone(dt)
end

return Units
