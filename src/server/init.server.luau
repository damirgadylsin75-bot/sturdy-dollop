-- Drag 2D: сервер. Строит трассу (две полосы в профиль), ведёт заезд:
-- дерево старта, реакция, фальстарт, финиш, награда, ИИ на верхней полосе.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.config)
local CarService = require(script.car_service)

Players.CharacterAutoLoads = false -- никакой ходьбы вообще

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
local pedal = Instance.new("RemoteEvent")
pedal.Name = "Pedal"
pedal.Parent = remotes
local gear = Instance.new("RemoteEvent")
gear.Name = "Gear"
gear.Parent = remotes

-- ===== ТРАССА (вид сбоку: полоса игрока внизу, ИИ выше) =====
local scene = Instance.new("Folder")
scene.Name = "Scene"
scene.Parent = workspace

local length = Config.Race.DistanceM * Config.Race.StudsPerMeter
local laneTop = Config.Race.PlayerLaneTop
local aiLaneTop = laneTop + Config.Race.LaneGap

local raceFolder = Instance.new("Folder")
raceFolder.Name = "Race"
raceFolder.Parent = scene
CarService.setParent(raceFolder)

local function strip(topY)
	local s = Instance.new("Part")
	s.Anchored = true
	s.Size = Vector3.new(60, 2, length + 220)
	s.Position = Vector3.new(0, topY - 1, -length / 2)
	s.Color = Config.color("Asphalt")
	s.Parent = scene
end
strip(laneTop)
strip(aiLaneTop)

-- стартовая и финишная линии через обе полосы
local function line(z, h)
	local l = Instance.new("Part")
	l.Anchored = true
	l.Size = Vector3.new(0.3, Config.Race.LaneGap + 8, h)
	l.Position = Vector3.new(30.2, (laneTop + aiLaneTop) / 2, z)
	l.Color = Config.color("Line")
	l.Parent = scene
end
line(0, 1.4)
line(-length, 2.4)

-- отметки дистанции каждые 100 м (глаз видит скорость)
for m = 100, math.floor(Config.Race.DistanceM), 100 do
	local z = -m * Config.Race.StudsPerMeter
	local marker = Instance.new("Part")
	marker.Anchored = true
	marker.Size = Vector3.new(0.2, Config.Race.LaneGap + 6, 0.5)
	marker.Position = Vector3.new(30.1, (laneTop + aiLaneTop) / 2, z)
	marker.Color = Config.color("Line")
	marker.Transparency = 0.55
	marker.Parent = scene
end

-- ===== ЗАДНИК: город пользователя, 9 слоёв параллакса =====
-- Слои стоят стеной ЗА трассой (камера на +X). Чем слой дальше, тем
-- медленнее он плывёт по экрану — глубина сама собой. Порядок в конфиге:
-- от дальнего к ближнему. Высоты растут с глубиной (дальние = больше неба).
local layerX = { -420, -360, -305, -255, -210, -170, -135, -105, -78 }
local layerH = { 620, 560, 500, 445, 390, 335, 285, 240, 200 }
local backdropLen = 3000
local backdropZ = -800

-- страховочное небо позади всего
local skyWall = Instance.new("Part")
skyWall.Anchored = true
skyWall.CanCollide = false
skyWall.CanQuery = false
skyWall.CastShadow = false
skyWall.Size = Vector3.new(2, 700, backdropLen)
skyWall.Position = Vector3.new(-450, 340, backdropZ)
skyWall.Color = Config.color("Sky")
skyWall.Parent = scene

for i, artId in Config.Art.CityLayers do
	local x = layerX[i] or (-100 - i * 40)
	local h = layerH[i] or 300
	local plane = Instance.new("Part")
	plane.Anchored = true
	plane.CanCollide = false
	plane.CanQuery = false
	plane.CastShadow = false
	plane.Size = Vector3.new(2, h, backdropLen)
	plane.Position = Vector3.new(x, h / 2 - 2, backdropZ)
	plane.Parent = scene

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Right -- сторона к камере
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 10
	gui.Parent = plane
	local img = Instance.new("ImageLabel")
	img.BackgroundTransparency = 1
	img.Size = UDim2.fromScale(1, 1)
	img.ScaleType = Enum.ScaleType.Stretch
	img.Image = artId
	img.Parent = gui
end

-- ===== ЗАЕЗД =====
local busy = false

local function setTree(text)
	state:SetAttribute("TreeText", text)
end

local function carBaseZ(model)
	local base = CarService.baseOf(model)
	return base and base.Position.Z or 0
end

startRace.OnServerEvent:Connect(function(player)
	if busy or state:GetAttribute("Phase") ~= "Garage" then return end
	busy = true

	-- свежие машины: игрок на нижней полосе, ИИ на верхней
	CarService.removeAll()
	local spawnY = laneTop + Config.Car2D.BodyHeight / 2 + Config.Car2D.WheelRadius + 0.15
	local playerCar, playerSt = CarService.buildCar("PlayerCar",
		CFrame.new(0, spawnY, Config.Race.StartZ), false, 0, raceFolder)
	local aiSpawnY = aiLaneTop + Config.Car2D.BodyHeight / 2 + Config.Car2D.WheelRadius + 0.15
	local aiCar, aiSt = CarService.buildCar("AICar",
		CFrame.new(0, aiSpawnY, Config.Race.StartZ), true, 0, raceFolder)

	state:SetAttribute("Phase", "Race")
	state:SetAttribute("ResultText", "")
	setTree("Приготовились…")
	task.wait(1)

	-- дерево: амбры одна за другой, затем зелёный
	for i = 1, Config.Race.TreeSteps do
		setTree(string.rep("●", i) .. "  (" .. (Config.Race.TreeSteps - i + 1) .. ")")
		task.wait(Config.Race.TreeInterval)
	end

	setTree("GO!")
	local greenAt = workspace:GetServerTimeNow()
	playerSt.green = true
	aiSt.green = true
	aiSt.gas = 1

	-- фальстарт: газ ДО зелёного
	local dqConn
	dqConn = pedal.OnServerEvent:Connect(function(plr, gasOn)
		if plr ~= player then return end
		if not playerSt.green and gasOn and not playerSt.dq then
			playerSt.dq = true
			setTree("ФАЛЬСТАРТ!")
		end
	end)

	-- реакция: первый газ ПОСЛЕ зелёного
	task.spawn(function()
		while not playerSt.reaction and not playerSt.dq do
			task.wait(0.03)
			if playerSt.gas > 0 and playerSt.green then
				playerSt.reaction = workspace:GetServerTimeNow() - greenAt
			end
		end
	end)

	-- ждём финиш обоих
	local deadline = greenAt + Config.Race.GreenHold + 60
	local aiTime, playerTime
	while workspace:GetServerTimeNow() < deadline do
		task.wait(0.05)
		local now = workspace:GetServerTimeNow()
		if not aiTime and carBaseZ(aiCar) <= -length then
			aiTime = now - greenAt
		end
		if not playerTime and carBaseZ(playerCar) <= -length then
			playerTime = now - greenAt
		end
		if playerTime and aiTime then break end
	end
	dqConn:Disconnect()

	-- итог и награда
	local reward = Config.Economy.BaseReward
	local resultText
	if playerSt.dq then
		reward = 0
		resultText = ("Фальстарт — без награды. ИИ: %s")
			:format(aiTime and string.format("%.2f с", aiTime) or "не финишировал")
	elseif playerTime then
		local won = aiTime == nil or playerTime <= aiTime
		if won then reward = reward + Config.Economy.WinBonus end
		if playerSt.reaction and playerSt.reaction < Config.Economy.ReactionGreat then
			reward = reward + Config.Economy.ReactionBonus
		end
		resultText = ("Вы: %.2f с (%s) | ИИ: %s | реакция %s")
			:format(playerTime, won and "ПОБЕДА" or "проигрыш",
				aiTime and string.format("%.2f с", aiTime) or "—",
				playerSt.reaction and string.format("%.2f с", playerSt.reaction) or "—")
	else
		reward = 0
		resultText = "Не финишировал — без награды"
	end

	local cash = state:GetAttribute("Cash") or 0
	state:SetAttribute("Cash", cash + reward)
	state:SetAttribute("ResultText", resultText)
	state:SetAttribute("LastReward", reward)
	setTree(resultText .. ("  +%d$"):format(reward))

	task.wait(4)
	CarService.removeCar(aiCar)
	CarService.setPedal(playerCar, false, false)
	state:SetAttribute("Phase", "Garage")
	busy = false
end)

pedal.OnServerEvent:Connect(function(player, gasOn, brakeOn)
	local car = workspace.Scene.Race:FindFirstChild("PlayerCar")
	if car then
		CarService.setPedal(car, gasOn == true, brakeOn == true)
	end
end)

gear.OnServerEvent:Connect(function(player, action)
	local car = workspace.Scene.Race:FindFirstChild("PlayerCar")
	if car then
		CarService.setGear(car, tostring(action))
	end
end)

print("Drag 2D server boot, v" .. Config.Version)
