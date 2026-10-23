-- Builds the visual city from generated map data.
-- v0.7 "realistic blocks": asphalt with sidewalks/curbs/lane dashes/zebra
-- crossings, warm rooftops with parapets and rooftop props, layered trees.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.config)

local City = {}

local folders = {}

local ASPHALT_W = 10       -- drivable width
local SIDEWALK_W = 2       -- each side
local CROSSWALK_AT = { 8.5, 10.3, 12.1, 13.9 } -- distance from node along edge

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

local function cyl(props, parent)
	props.Shape = Enum.PartType.Cylinder
	return part(props, parent)
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

	local asphaltColor = Config.color("Asphalt")
	local sidewalkColor = Config.color("Sidewalk")
	local curbColor = Config.color("Curb")
	local laneColor = Config.color("LaneMark")

	-- roads -----------------------------------------------------------------
	for _, e in ipairs(city.edges) do
		local pa = city.nodes[e.a].pos
		local pb = city.nodes[e.b].pos
		local dir = pb - pa
		local len = dir.Magnitude
		local mid = (pa + pb) / 2
		local yaw = math.atan2(dir.X, dir.Y)
		local cf = CFrame.new(mid.X, 0, mid.Y) * CFrame.Angles(0, yaw, 0)

		-- asphalt bed (overlaps into intersections)
		part({
			Name = "Asphalt",
			Size = Vector3.new(ASPHALT_W, 0.5, len + 14),
			CFrame = cf,
			Color = asphaltColor,
			CastShadow = false,
		}, static)

		-- sidewalks with curb line (trimmed back from intersections)
		local swLen = len - 10
		if swLen > 2 then
			local swMid = 5 + swLen / 2
			for side = -1, 1, 2 do
				local off = side * (ASPHALT_W / 2 + SIDEWALK_W / 2)
				local p = cf * CFrame.new(off, 0, 0)
				part({
					Name = "Sidewalk",
					Size = Vector3.new(SIDEWALK_W, 0.7, swLen),
					CFrame = CFrame.new(p.X, 0, p.Z) * CFrame.Angles(0, yaw, 0),
					Color = sidewalkColor,
					CastShadow = false,
				}, static)
				-- curb stripe on the road side of the sidewalk
				local c = cf * CFrame.new(off - side * (SIDEWALK_W / 2 + 0.15), 0, 0)
				part({
					Name = "Curb",
					Size = Vector3.new(0.3, 0.62, swLen),
					CFrame = CFrame.new(c.X, 0, c.Z) * CFrame.Angles(0, yaw, 0),
					Color = curbColor,
					CastShadow = false,
				}, static)
			end
		end

		-- center dashes (kept clear of crossings)
		local dashStart, dashStep = 16, 24
		if len > dashStart * 2 + 6 then
			local k = 0
			local d = dashStart
			while d <= len - dashStart do
				local dp = pa:Lerp(pb, d / len)
				part({
					Name = "LaneDash",
					Size = Vector3.new(0.7, 0.06, 5),
					CFrame = CFrame.new(dp.X, 0, dp.Y) * CFrame.Angles(0, yaw, 0),
					Color = laneColor,
					CastShadow = false,
				}, static)
				k = k + 1
				d = dashStart + k * dashStep
			end
		end

		-- zebra crossings at both ends
		for _, nodePos in ipairs({ pa, pb }) do
			local sign = (nodePos == pa) and 1 or -1
			for _, d in ipairs(CROSSWALK_AT) do
				local zp = nodePos + dir.Unit * (d * sign)
				part({
					Name = "Zebra",
					Size = Vector3.new(ASPHALT_W - 1, 0.07, 0.9),
					CFrame = CFrame.new(zp.X, 0, zp.Y) * CFrame.Angles(0, yaw, 0),
					Color = laneColor,
					CastShadow = false,
				}, static)
			end
		end
	end

	-- intersection plates ----------------------------------------------------
	for _, node in pairs(city.nodes) do
		part({
			Name = "Intersection",
			Size = Vector3.new(14, 0.5, 14),
			CFrame = CFrame.new(node.pos.X, 0, node.pos.Y),
			Color = asphaltColor,
			CastShadow = false,
		}, static)
	end

	-- parks with layered trees ------------------------------------------------
	local parkColor = Config.color("Park")
	local trunkColor = Config.color("TreeTrunk")
	local crownA = Config.color("TreeCrown")
	local crownB = Config.color("TreeCrownMid")
	local crownC = Config.color("TreeCrownTop")
	local treeOffsets = {
		{ -0.28, 0.05 }, { 0.10, -0.25 }, { 0.26, 0.18 },
		{ -0.05, 0.30 }, { 0.30, -0.06 }, { -0.22, -0.22 },
	}
	for pi, park in ipairs(city.parks) do
		part({
			Name = "Park",
			Size = Vector3.new(park.size.X, 0.45, park.size.Y),
			CFrame = CFrame.new(park.pos.X, 0, park.pos.Y),
			Color = parkColor,
			CastShadow = false,
		}, static)
		for ti, off in ipairs(treeOffsets) do
			-- deterministic jitter so parks don't look cloned
			local jx = math.sin(pi * 3.1 + ti * 1.7) * 3
			local jz = math.cos(pi * 2.3 + ti * 2.1) * 3
			local tx = park.pos.X + off[1] * park.size.X + jx
			local tz = park.pos.Y + off[2] * park.size.Y + jz
			local s = 0.85 + ((math.sin(pi * 5.7 + ti * 3.3) + 1) / 2) * 0.35
			part({
				Name = "TreeTrunk",
				Size = Vector3.new(0.9 * s, 3, 0.9 * s),
				CFrame = CFrame.new(tx, 1.5, tz),
				Color = trunkColor,
				CastShadow = false,
			}, static)
			cyl({
				Name = "TreeCrownA",
				Size = Vector3.new(2.2 * s, 7 * s, 7 * s),
				CFrame = CFrame.new(tx, 3.4, tz) * CFrame.Angles(0, 0, math.rad(90)),
				Color = crownA,
				CastShadow = false,
			}, static)
			cyl({
				Name = "TreeCrownB",
				Size = Vector3.new(2 * s, 5.2 * s, 5.2 * s),
				CFrame = CFrame.new(tx, 4.9, tz) * CFrame.Angles(0, 0, math.rad(90)),
				Color = crownB,
				CastShadow = false,
			}, static)
			cyl({
				Name = "TreeCrownC",
				Size = Vector3.new(1.6 * s, 3.2 * s, 3.2 * s),
				CFrame = CFrame.new(tx, 6.3, tz) * CFrame.Angles(0, 0, math.rad(90)),
				Color = crownC,
				CastShadow = false,
			}, static)
		end
	end

	-- buildings: dark body + warm rooftop + props -----------------------------
	local bodyBase = Config.color("Building")
	local shadowColor = Config.color("BuildingShadow")
	local trimColor = Config.color("RoofTrim")
	for _, b in ipairs(city.buildings) do
		local shade = 0.85 + b.shade * 0.3
		part({
			Name = "BuildingShadow",
			Size = Vector3.new(b.size.X + 3, 0.3, b.size.Y + 3),
			CFrame = CFrame.new(b.pos.X, 0.2, b.pos.Y),
			Color = shadowColor,
			CastShadow = false,
		}, static)
		part({
			Name = "Building",
			Size = Vector3.new(b.size.X, b.height, b.size.Y),
			CFrame = CFrame.new(b.pos.X, b.height / 2, b.pos.Y),
			Color = Color3.new(
				math.clamp(bodyBase.R * shade, 0, 1),
				math.clamp(bodyBase.G * shade, 0, 1),
				math.clamp(bodyBase.B * shade, 0, 1)
			),
		}, static)

		-- rooftop slab (slight overhang) in the warm palette
		local roofIdx = math.min(math.floor(b.shade * #Config.RoofColors) + 1, #Config.RoofColors)
		local roofColor = Color3.fromHex(Config.RoofColors[roofIdx])
		part({
			Name = "Roof",
			Size = Vector3.new(b.size.X + 1.2, 0.9, b.size.Y + 1.2),
			CFrame = CFrame.new(b.pos.X, b.height + 0.45, b.pos.Y),
			Color = roofColor,
			CastShadow = false,
		}, static)
		-- parapet trim ring
		part({
			Name = "RoofTrim",
			Size = Vector3.new(b.size.X + 1.8, 0.5, b.size.Y + 1.8),
			CFrame = CFrame.new(b.pos.X, b.height + 0.2, b.pos.Y),
			Color = trimColor,
			CastShadow = false,
		}, static)

		-- rooftop props, deterministic
		if b.shade > 0.55 then
			part({
				Name = "RoofAC",
				Size = Vector3.new(2.4, 1.3, 2),
				CFrame = CFrame.new(b.pos.X + b.size.X / 4, b.height + 1.55, b.pos.Y - b.size.Y / 4),
				Color = Color3.fromRGB(112, 118, 130),
				CastShadow = false,
			}, static)
		end
		if b.height > 55 then
			cyl({
				Name = "WaterTank",
				Size = Vector3.new(3.2, 3, 3),
				CFrame = CFrame.new(b.pos.X - b.size.X / 4, b.height + 2.7, b.pos.Y + b.size.Y / 4)
					* CFrame.Angles(0, 0, math.rad(90)),
				Color = Color3.fromRGB(94, 74, 58),
				CastShadow = false,
			}, static)
		end
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
