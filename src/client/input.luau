-- Placement and targeting: ghost preview with snapping, hotkeys, commands.
-- Build tools work in Planning; strike tools work in Live. The client shows
-- the ghost, but the server re-validates every order.

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("config"))
local Graph = require(ReplicatedStorage.Shared.graph)

local CameraRig = require(script.Parent.camera)

local Input = {}

local city
local state
local commandEvent

local mode = nil -- nil | { kind = "build"|"strike", tool = id }
local ghost = nil
local zoneRadius = Config.SafeZone.Radius
local hintLabel

local toolsByKey = {}
local toolById = {}

for _, info in ipairs(Config.toolInfo()) do
	toolsByKey[info.key] = info
	toolById[info.id] = info
end

local function attr(n)
	return state:GetAttribute(n)
end

local function phase()
	return attr("Phase")
end

local function setHint(text)
	hintLabel.Text = text or ""
end

local function destroyGhost()
	if ghost then
		ghost:Destroy()
		ghost = nil
	end
end

local function makeGhost(kind, size, color)
	destroyGhost()
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Transparency = 0.55
	p.Color = color
	if kind == "ball" then
		p.Shape = Enum.PartType.Ball
	elseif kind == "disc" then
		p.Shape = Enum.PartType.Cylinder
	else
		p.Shape = Enum.PartType.Block
	end
	p.Size = size
	p.Parent = workspace:FindFirstChild("CityRoot") or workspace
	return p
end

local function ghostDiscRadius(x, z, radius, ok)
	local p = makeGhost("disc", Vector3.new(0.6, radius * 2, radius * 2), ok and Color3.fromRGB(255, 90, 90) or Color3.fromRGB(140, 140, 140))
	p.CFrame = CFrame.new(x, 1.1, z) * CFrame.Angles(0, 0, math.rad(90))
end

local HINTS = {
	barricade = "Баррикада: ЛКМ на улице — поставить (можно несколько) • ПКМ/Esc — выйти",
	sniper = "Снайпер: ЛКМ на крыше дома — поставить • ПКМ/Esc — выйти",
	safezone = "Зона безопасности: ЛКМ — развернуть • колесо мыши — радиус",
	evac = "Эвакуация: ЛКМ у перекрёстка",
	airstrike = "Авиаудар: ЛКМ — вызвать. Придёт через "
		.. Config.Abilities.Airstrike.Delay .. " с, ляжет линией вдоль улицы",
	missile = "Ракета: ЛКМ — удар. Почти мгновенно, большой радиус",
}

function Input.cancel()
	mode = nil
	destroyGhost()
	setHint("")
end

function Input.getTool()
	return mode and mode.tool or nil
end

function Input.setTool(id)
	if mode and mode.tool == id then
		Input.cancel()
		return
	end
	local info = toolById[id]
	if not info then return end
	if phase() ~= info.phase then
		if info.phase == "Planning" then
			setHint("Строить можно только в фазе подготовки")
		else
			setHint("Авиация доступна только во время симуляции")
		end
		task.delay(2.5, function()
			if not mode then setHint("") end
		end)
		return
	end
	mode = { kind = info.phase == "Planning" and "build" or "strike", tool = id }
	setHint(HINTS[id])
end

local function affordBuild(tool)
	local info = toolById[tool]
	if not info then return false end
	if (attr("PrepBudget") or 0) < info.cost then return false end
	local max = { safezone = Config.Prep.MaxSafeZones, barricade = Config.Prep.MaxBarricades, sniper = Config.Prep.MaxSnipers, evac = Config.Prep.MaxExtraEvacs }
	local countAttr = { safezone = "SafeZones", barricade = "Barricades", sniper = "Snipers", evac = "EvacExtra" }
	if (attr(countAttr[tool]) or 0) >= max[tool] then return false end
	return true
end

local function updateGhost()
	if not mode then return end
	local p = CameraRig.groundPoint()
	if not p then
		if ghost then ghost.Transparency = 1 end
		return
	end
	if ghost then ghost.Transparency = 0.55 end

	local ok = true
	if mode.kind == "build" then
		ok = affordBuild(mode.tool)
	end

	if mode.tool == "barricade" then
		local point, edge, dist = Graph.nearestEdgePoint(city, p)
		local inRange = dist <= Config.Prep.SnapEdgeDist
		if not ghost or ghost.Name ~= "BarGhost" then
			ghost = makeGhost("block", Vector3.new(Config.Map.StreetWidth + 6, 3.2, 2.4), Config.color("Barricade"))
			ghost.Name = "BarGhost"
		end
		local dir = (city.nodes[edge.b].pos - city.nodes[edge.a].pos).Unit
		ghost.CFrame = CFrame.new(point.X, 1.8, point.Y) * CFrame.Angles(0, math.atan2(dir.X, dir.Y), 0)
		ghost.Color = (ok and inRange) and Config.color("Barricade") or Color3.fromRGB(255, 80, 80)
	elseif mode.tool == "sniper" then
		local building = nil
		for _, b in ipairs(city.buildings) do
			if math.abs(p.X - b.pos.X) <= b.size.X / 2 + 2 and math.abs(p.Y - b.pos.Y) <= b.size.Y / 2 + 2 then
				building = b
				break
			end
		end
		if not ghost or ghost.Name ~= "SnGhost" then
			ghost = makeGhost("ball", Vector3.new(3.2, 3.2, 3.2), Config.color("Sniper"))
			ghost.Name = "SnGhost"
		end
		if building then
			local rx = math.clamp(p.X, building.pos.X - building.size.X / 2 + 2, building.pos.X + building.size.X / 2 - 2)
			local rz = math.clamp(p.Y, building.pos.Y - building.size.Y / 2 + 2, building.pos.Y + building.size.Y / 2 - 2)
			ghost.CFrame = CFrame.new(rx, building.height + 1.6, rz)
			ghost.Color = ok and Config.color("Sniper") or Color3.fromRGB(255, 80, 80)
		else
			ghost.CFrame = CFrame.new(p.X, 1.6, p.Y)
			ghost.Color = Color3.fromRGB(255, 80, 80)
		end
	elseif mode.tool == "safezone" then
		local fit = p.Y <= city.waterZ - Config.SafeZone.Radius - 6
		if not ghost or ghost.Name ~= "ZoneGhost" then
			ghost = makeGhost("disc", Vector3.new(0.6, zoneRadius * 2, zoneRadius * 2), Config.color("SafeZone"))
			ghost.Name = "ZoneGhost"
		end
		ghost.Size = Vector3.new(0.6, zoneRadius * 2, zoneRadius * 2)
		ghost.CFrame = CFrame.new(p.X, 1.1, p.Y) * CFrame.Angles(0, 0, math.rad(90))
		ghost.Color = (ok and fit) and Config.color("SafeZone") or Color3.fromRGB(255, 80, 80)
	elseif mode.tool == "evac" then
		local nodeId = Graph.nearestNodeWithin(city, p, Config.Prep.SnapNodeDist)
		if not ghost or ghost.Name ~= "EvacGhost" then
			ghost = makeGhost("disc", Vector3.new(24, 5, 5), Config.color("Evac"))
			ghost.Name = "EvacGhost"
		end
		if nodeId then
			local np = city.nodes[nodeId].pos
			ghost.CFrame = CFrame.new(np.X, 13, np.Y) * CFrame.Angles(0, 0, math.rad(90))
			ghost.Color = ok and Config.color("Evac") or Color3.fromRGB(255, 80, 80)
		else
			ghost.CFrame = CFrame.new(p.X, 13, p.Y) * CFrame.Angles(0, 0, math.rad(90))
			ghost.Color = Color3.fromRGB(255, 80, 80)
		end
	elseif mode.tool == "airstrike" then
		strikeGhost(p.X, p.Y, Config.Abilities.Airstrike.Radius, (attr("CommandPoints") or 0) >= Config.Costs.Airstrike)
	elseif mode.tool == "missile" then
		strikeGhost(p.X, p.Y, Config.Abilities.Missile.Radius, (attr("CommandPoints") or 0) >= Config.Costs.Missile)
	end
end

local function tryUse()
	if not mode then return end
	local p = CameraRig.groundPoint()
	if not p then return end
	if mode.kind == "build" then
		commandEvent:FireServer({ type = "place", tool = mode.tool, x = p.X, z = p.Y })
		if mode.tool == "safezone" or mode.tool == "evac" then
			Input.cancel() -- single-placement tools
		end
	else
		commandEvent:FireServer({ type = "strike", kind = mode.tool, x = p.X, z = p.Y })
	end
end

-- Called on round restart: the seed changes, so the client regenerates
-- the same city data the server built and re-arms snapping.
function Input.setCity(newCityData)
	Input.cancel()
	city = newCityData
end

function Input.init(cityData)
	city = cityData
	state = ReplicatedStorage:WaitForChild(Config.Net.StateFolder)
	local remotesFolder = ReplicatedStorage:WaitForChild(Config.Net.RemotesFolder)
	commandEvent = remotesFolder:WaitForChild(Config.Net.Command)

	-- phase transitions drop incompatible tool modes (build -> Live, etc.)
	state:GetAttributeChangedSignal("Phase"):Connect(function()
		if not mode then return end
		local info = toolById[mode.tool]
		if info and phase() ~= info.phase then
			Input.cancel()
		end
	end)

	local gui = Instance.new("ScreenGui")
	gui.Name = "InputHints"
	gui.ResetOnSpawn = false
	gui.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")

	hintLabel = Instance.new("TextLabel")
	hintLabel.BackgroundTransparency = 1
	hintLabel.AnchorPoint = Vector2.new(0.5, 1)
	hintLabel.Position = UDim2.new(0.5, 0, 1, -100)
	hintLabel.Size = UDim2.new(0, 1000, 0, 22)
	hintLabel.Font = Enum.Font.Gotham
	hintLabel.TextSize = 15
	hintLabel.TextColor3 = Color3.fromRGB(154, 166, 184)
	hintLabel.TextStrokeTransparency = 0.6
	hintLabel.Text = ""
	hintLabel.Parent = gui

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.Space then
			if phase() == "Live" then
				commandEvent:FireServer({ type = "pause" })
			end
		elseif input.KeyCode == Enum.KeyCode.F then
			if phase() == "Live" then
				commandEvent:FireServer({ type = "speed" })
			end
		elseif input.KeyCode == Enum.KeyCode.Escape then
			Input.cancel()
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
			tryUse()
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			Input.cancel()
		else
			local info = toolsByKey[input.KeyCode]
			if info then
				Input.setTool(info.id)
			end
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			if mode and mode.tool == "safezone" then
				zoneRadius = math.clamp(zoneRadius + (input.Position.Z > 0 and 5 or -5), 26, 64)
			else
				CameraRig.zoomBy(input.Position.Z)
			end
		end
	end)

	RunService:BindToRenderStep("InputGhost", Enum.RenderPriority.Input.Value + 1, function()
		if mode then
			updateGhost()
		end
	end)
end

return Input
