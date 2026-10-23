-- Deterministic schematic city generator.
-- The same seed produces the same city on the server and on every client,
-- so clients can snap placements without replicating any map data.

local Config = require(script.Parent.config)

local MapGen = {}

local SECTOR_LETTERS = { "А", "Б", "В", "Г", "Д", "Е", "Ж", "З", "И", "К", "Л", "М", "Н" }

function MapGen.generate(seed)
	local rng = Random.new(seed)
	local cfg = Config.Map
	local n = cfg.GridSize
	local spacing = cfg.NodeSpacing
	local half = (n - 1) * spacing / 2

	-- Street grid ----------------------------------------------------------
	local nodes = {}
	local grid = {}
	local id = 0
	for i = 1, n do
		grid[i] = {}
		for j = 1, n do
			id = id + 1
			grid[i][j] = id
			nodes[id] = {
				id = id,
				col = i,
				row = j,
				pos = Vector2.new((i - 1) * spacing - half, (j - 1) * spacing - half),
				edges = {},
			}
		end
	end

	local edges = {}
	local edgeIndex = {}
	local function connect(a, b)
		local key
		if a < b then
			key = tostring(a) .. "_" .. tostring(b)
		else
			key = tostring(b) .. "_" .. tostring(a)
		end
		if edgeIndex[key] then return end
		local e = { a = a, b = b, key = key }
		edgeIndex[key] = e
		edges[#edges + 1] = e
		local na, nb = nodes[a], nodes[b]
		na.edges[#na.edges + 1] = b
		nb.edges[#nb.edges + 1] = a
	end

	for i = 1, n do
		for j = 1, n do
			if i < n then connect(grid[i][j], grid[i + 1][j]) end
			if j < n then connect(grid[i][j], grid[i][j + 1]) end
		end
	end

	-- Blocks: parks and buildings -----------------------------------------
	local buildings = {}
	local parks = {}
	for i = 1, n - 1 do
		for j = 1, n - 1 do
			local cx = nodes[grid[i][j]].pos.X + spacing / 2
			local cz = nodes[grid[i][j]].pos.Y + spacing / 2
			local roll = rng:NextNumber()
			if roll < cfg.ParkChance then
				parks[#parks + 1] = {
					pos = Vector2.new(cx, cz),
					size = Vector2.new(spacing - 22, spacing - 22),
				}
			elseif roll < cfg.ParkChance + cfg.BuildingChance then
				local interior = spacing - 26 -- keep clear of the streets
				local w = interior * (0.45 + rng:NextNumber() * 0.5)
				local d = interior * (0.45 + rng:NextNumber() * 0.5)
				local jitterX = (interior - w) * (rng:NextNumber() - 0.5)
				local jitterZ = (interior - d) * (rng:NextNumber() - 0.5)
				local height
				if rng:NextNumber() < cfg.TowerChance then
					height = 70 + rng:NextNumber() * 55
				else
					height = 10 + rng:NextNumber() * 38
				end
				buildings[#buildings + 1] = {
					pos = Vector2.new(cx + jitterX, cz + jitterZ),
					size = Vector2.new(w, d),
					height = height,
					shade = rng:NextNumber(),
				}
			end
		end
	end

	-- Default evacuation point: a pier on the south shore ------------------
	local evacCol = math.floor(n / 2) + rng:NextInteger(-2, 2)
	evacCol = math.clamp(evacCol, 2, n - 1)
	local evacNode = grid[evacCol][n]

	-- Outbreak points: far from the pier and from each other ---------------
	local outbreakPoints = {}
	local attempts = 0
	while #outbreakPoints < #Config.Simulation.Waves and attempts < 400 do
		attempts = attempts + 1
		local i = rng:NextInteger(1, n - 1)
		local j = rng:NextInteger(1, n - 1)
		local p = Vector2.new(
			nodes[grid[i][j]].pos.X + spacing / 2,
			nodes[grid[i][j]].pos.Y + spacing / 2
		)
		local ok = true
		if (p - nodes[evacNode].pos).Magnitude < 360 then ok = false end
		if ok then
			for _, q in ipairs(outbreakPoints) do
				if (p - q).Magnitude < 260 then
					ok = false
					break
				end
			end
		end
		if ok then outbreakPoints[#outbreakPoints + 1] = p end
	end
	while #outbreakPoints < #Config.Simulation.Waves do
		outbreakPoints[#outbreakPoints + 1] = Vector2.new(-half + 40, -half + 40)
	end

	-- Civilian spawn spots along random streets ----------------------------
	local civSpawns = {}
	for _ = 1, Config.Simulation.Civilians do
		local e = edges[rng:NextInteger(1, #edges)]
		local t = rng:NextNumber()
		civSpawns[#civSpawns + 1] = nodes[e.a].pos:Lerp(nodes[e.b].pos, t)
	end

	local city = {
		seed = seed,
		n = n,
		spacing = spacing,
		half = half,
		nodes = nodes,
		nodeGrid = grid,
		edgeIndex = edgeIndex,
		edges = edges,
		buildings = buildings,
		parks = parks,
		evacNode = evacNode,
		outbreakPoints = outbreakPoints,
		civSpawns = civSpawns,
		waterZ = half + 44,
	}

	function city.sectorName(pos)
		local col = math.clamp(math.floor((pos.X + half) / spacing) + 1, 1, n)
		local row = math.clamp(math.floor((pos.Y + half) / spacing) + 1, 1, n)
		return SECTOR_LETTERS[col] .. "-" .. tostring(row)
	end

	return city
end

return MapGen
