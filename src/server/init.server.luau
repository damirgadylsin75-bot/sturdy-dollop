-- Drag II: сервер. Строит гараж/стрит, держит заезд: дерево старта,
-- реакция, финиш, награда, ИИ-соперник на второй полосе.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.config)
local CarService = require(script.car_service)

Players.CharacterAutoLoads = false -- никакого ходьбы: игрок сидит в машине

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
local carInput = Instance.new("RemoteEvent")
carInput.Name = "CarInput"
carInput.Parent = remotes

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
	strip.Size = Vector3.new(Config.Race.LaneWidth - 4, 2, length + 220)
	strip.Position = Vector3.new(offset, 1, -length / 2)
	strip.Color = color
	strip.Parent = scene
end
lane(-Config.Race.LaneWidth / 2, Config.color("Asphalt"))
lane(Config.Race.LaneWidth / 2, Config.color("Asphalt"))

local function line(z, color, h)
	local l = Instance.new("Part")
	l.Anchored = true
	l.Size = Vector3.new(Config.Race.LaneWidth * 2, 0.2, h)
	l.Position = Vector3.new(0, 2.1, z)
	l.Color = color
	l.Parent = scene
end
line(0, Config.color("Line"), 1.2)
line(-length, Config.color("Line"), 2)

local raceFolder = Instance.new("Folder")
raceFolder.Name = "Race"
raceFolder.Parent = scene

CarService.startup(state, raceFolder)

local function startCF(laneSign)
	return CFrame.new(laneSign * Config.Race.LaneWidth / 2, 0.5, Config.Race.StartZ)
end

-- ===== ЗАЕЗД =====
local busy = false

local function setTree(text)
	state:SetAttribute("TreeText", text)
end

startRace.OnServerEvent:Connect(function(player)
	if busy or state:GetAttribute("Phase") ~= "Garage" then return end
	if not workspace:FindFirstChild("Scene") then return end
	busy = true

	-- свежие машины
	CarService.despawnAll()
	local playerCar, playerSt = CarService.buildCar("PlayerCar", startCF(-1), false)
	local aiCar, aiSt = CarService.buildCar("AICar", startCF(1), true)

	-- игрок сразу в сиденье, встать нельзя
	CarService.seatPlayer(player, playerCar)

	state:SetAttribute("Phase", "Race")
	setTree("Приготовились…")
	task.wait(1)

	-- дерево: 3 амбры с интервалом, затем зелёный
	for i = 1, Config.Race.TreeSteps do
		setTree(string.rep("●", i) .. "  (" .. (Config.Race.TreeSteps - i + 1) .. ")")
		task.wait(Config.Race.TreeInterval)
	end

	setTree("GO!")
	local greenAt = workspace:GetServerTimeNow()
	playerSt.green = true
	aiSt.green = true
	aiSt.aiThrottle = 1 -- ИИ уходит сразу на зелёном

	-- реакция игрока: первый газ после зелёного
	local reactionConn
	reactionConn = task.spawn(function()
		while not playerSt.reaction do
			task.wait(0.05)
			if playerSt.seat.Throttle > 0 then
				playerSt.reaction = workspace:GetServerTimeNow() - greenAt
			end
		end
	end)

	-- фальстарт: газ ДО зелёного
	task.spawn(function()
		while not playerSt.green do
			task.wait(0.05)
			if playerSt.seat.Throttle > 0 then
				playerSt.dq = true
				setTree("ФАЛЬСТАРТ! Дисквалификация")
				break
			end
		end
	end)

	-- ждём финиш (максимум GreenHold + 60 сек)
	local deadline = greenAt + Config.Race.GreenHold + 60
	local aiTime, playerTime
	while workspace:GetServerTimeNow() < deadline do
		task.wait(0.05)
		local now = workspace:GetServerTimeNow()
		if not aiTime and aiSt.base.Position.Z <= -length then
			aiTime = now - greenAt
		end
		if not playerTime and playerSt.base.Position.Z <= -length then
			playerTime = now - greenAt
		end
		if playerTime and aiTime then break end
	end

	-- итог
	local cash = state:GetAttribute("Cash") or 0
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

	cash = cash + reward
	state:SetAttribute("Cash", cash)
	state:SetAttribute("ResultText", resultText)
	state:SetAttribute("LastReward", reward)
	setTree(resultText)

	-- откат в гараж: ИИ уходит, машина игрока едет назад на старт
	task.wait(4)
	CarService.removeCar(aiCar)
	if playerCar.Parent then
		playerCar:PivotTo(startCF(-1))
	end
	state:SetAttribute("Phase", "Garage")
	busy = false
end)

-- ручная коробка: клиент шлёт "mode"/"up"/"down"
carInput.OnServerEvent:Connect(function(player, action)
	local char = player.Character
	local seat = char and char:FindFirstChildOfClass("Humanoid")
			and char.Humanoid.SeatPart
	if not seat or not seat.Parent then return end
	local car = seat.Parent
	if car and car.Name == "PlayerCar" then
		CarService.setGear(car, action)
	end
end)

print("Drag II server boot, v" .. Config.Version)
