-- Drag II: сервер. Строит гараж/стрит, держит стейт заезда (v0.1 — каркас).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.config)

Players.CharacterAutoLoads = false -- никакого ходьбы: гараж = экран

local state = Instance.new("Folder")
state.Name = Config.Net.StateFolder
state.Parent = ReplicatedStorage
state:SetAttribute("Version", Config.Version)
state:SetAttribute("Cash", Config.Economy.StartCash)
state:SetAttribute("Phase", "Garage")

local remotes = Instance.new("Folder")
remotes.Name = Config.Net.RemotesFolder
remotes.Parent = ReplicatedStorage
local startRace = Instance.new("RemoteEvent")
startRace.Name = "StartRace"
startRace.Parent = remotes

-- сцена: гаражная площадка + прямой стрип на две полосы
local scene = Instance.new("Folder")
scene.Name = "Scene"
scene.Parent = workspace

local ground = Instance.new("Part")
ground.Anchored = true
ground.Size = Vector3.new(300, 2, 2200)
ground.Position = Vector3.new(0, -1, 0)
ground.Color = Config.color("Ground")
ground.Parent = scene

local length = Config.Race.DistanceM * Config.Race.StudsPerMeter
local function lane(offset, color)
	local strip = Instance.new("Part")
	strip.Anchored = true
	strip.Size = Vector3.new(Config.Race.LaneWidth - 4, 0.4, length + 220)
	strip.Position = Vector3.new(offset, 0, -length / 2)
	strip.Color = color
	strip.Parent = scene
end
lane(-Config.Race.LaneWidth / 2, Config.color("Asphalt"))
lane(Config.Race.LaneWidth / 2, Config.color("Asphalt"))

-- стартовая линия и финиш
local function line(z, color, h)
	local l = Instance.new("Part")
	l.Anchored = true
	l.Size = Vector3.new(Config.Race.LaneWidth * 2, 0.2, h)
	l.Position = Vector3.new(0, 0.15, z)
	l.Color = color
	l.Parent = scene
end
line(0, Config.color("Line"), 1.2)
line(-length, Config.color("Line"), 2)

startRace.OnServerEvent:Connect(function(player)
	if state:GetAttribute("Phase") ~= "Garage" then return end
	state:SetAttribute("Phase", "Race")
	-- v0.1: заглушка заезда; сюда встают дерево старта, машина игрока, ИИ и таймер
	task.delay(3, function()
		state:SetAttribute("Phase", "Garage")
	end)
end)

print("Drag II server boot, v" .. Config.Version)
