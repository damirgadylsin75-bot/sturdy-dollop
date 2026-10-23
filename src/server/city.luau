-- Builds the visual schematic city from generated map data.
-- Flat plates, muted colors, extruded blocks: a "navigation app" look.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.config)

local City = {}

local folders = {}

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

function City.folders()
	return folders
end

function City.build(city)
	City.destroyAll()

	local root = Instance.new("Folder")
	root.Name = "CityRoot"
	root.Parent = workspace

	local static = Instance.new("Folder")
	static.Name = "City"
	static.Parent = root

	part({
		Name = "Ground",
		Size = Vector3.new(1800, 2, 1800),
		CFrame = CFrame.new(0, -1, 0),
		Color = Config.color("Ground"),
		CastShadow = false,
	}, static)

	local water = part({
		Name = "Water",
		Size = Vector3.new(1800, 2, 800),
		CFrame = CFrame.new(0, -0.55, city.waterZ + 400),
		Color = Config.color("Water"),
		CastShadow = false,
	}, static)
	water.Transparency = 0.2

	local streetColor = Config.color("Street")
	for _, e in ipairs(city.edges) do
		local pa = city.nodes[e.a].pos
		local pb = city.nodes[e.b].pos
		local dir = pb - pa
		local len = dir.Magnitude
		local mid = (pa + pb) / 2
		local yaw = math.atan2(dir.X, dir.Y)
		part({
			Name = "Street",
			Size = Vector3.new(Config.Map.StreetWidth, 0.4, len + Config.Map.StreetWidth),
			CFrame = CFrame.new(mid.X, 0, mid.Y) * CFrame.Angles(0, yaw, 0),
			Color = streetColor,
			CastShadow = false,
		}, static)
	end

	for _, park in ipairs(city.parks) do
		part({
			Name = "Park",
			Size = Vector3.new(park.size.X, 0.45, park.size.Y),
			CFrame = CFrame.new(park.pos.X, 0, park.pos.Y),
			Color = Config.color("Park"),
			CastShadow = false,
		}, static)
	end

	local base = Config.color("Building")
	for _, b in ipairs(city.buildings) do
		local shade = 0.85 + b.shade * 0.3
		part({
			Name = "Building",
			Size = Vector3.new(b.size.X, b.height, b.size.Y),
			CFrame = CFrame.new(b.pos.X, b.height / 2, b.pos.Y),
			Color = Color3.new(
				math.clamp(base.R * shade, 0, 1),
				math.clamp(base.G * shade, 0, 1),
				math.clamp(base.B * shade, 0, 1)
			),
		}, static)
	end

	local function makeFolder(name, parent)
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
		return f
	end

	local pop = makeFolder("Population", root)
	folders.root = root
	folders.city = static
	folders.civs = makeFolder("Civilians", pop)
	folders.zoms = makeFolder("Zombies", pop)
	folders.units = makeFolder("Units", root)
	folders.marks = makeFolder("Marks", root)

	return folders
end

function City.destroyAll()
	if folders.root then
		folders.root:Destroy()
	end
	folders = {}
end

return City
