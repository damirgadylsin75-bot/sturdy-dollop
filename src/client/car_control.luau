-- DragDrive: наш «мозг» машины. Чужие скрипты модели вычищены при захвате,
-- поэтому газ/тормоз/передачи делает этот скрипт: он читает Tune A-Chassis,
-- считает кривую момента (shared/drivetrain) и крутит хинжи колёс
-- (#AV — привод, #BV — тормоз). Машина — без персонажа: физику отдаём
-- клиенту-владельцу (SetNetworkOwner на сервере), так что всё это работает.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.config)
local Drivetrain = require(ReplicatedStorage.Shared.drivetrain)

local player = Players.LocalPlayer

local Drive = {}

local car -- модель PlayerCar
local wheels -- { {part=, av=, bv=, driven=, radius=} }
local engine -- спецификация для Drivetrain
local ratios -- таблица передач из Tune
local refPart -- по чему меряем скорость
local rpm = 0
local gear = 1
local reversing = false
local mode = "Auto" -- "Auto" | "Manual"
local throttle, brake = 0, 0

local function firstOfClass(container, class)
	for _, d in container:GetChildren() do
		if d:IsA(class) then return d end
	end
	return nil
end

-- Собрать спецификацию двигателя из Tune (с запасными значениями).
local function engineSpec(tune)
	local e = {}
	e.idleRpm = tune.IdleRPM or 1000
	e.idleTorque = tune.IdleTorque or 315
	e.idleShape = tune.IdleTorqueCurve or 0.275
	e.peakTorque = tune.PeakTorque or 390
	e.peakRpm = tune.PeakTorqueRPM or 2500
	e.redline = tune.Redline or 7500
	e.redlineTorque = tune.RedlineTorque or 160
	e.redShape = tune.RedlineTorqueCurve or 0.31
	e.shiftRpm = tune.ShiftRPM or 7000
	e.gearCount = 1
	local maxGear = 1
	if type(tune.GearRatios) == "table" then
		for g in pairs(tune.GearRatios) do
			if type(g) == "number" and g >= 1 and g > maxGear then maxGear = g end
		end
		e.gearCount = maxGear
	end
	e.finalDrive = tune.FinalDrive or 3.6
	return e
end

local function collectWheels(carModel, tune)
	local folder = carModel:FindFirstChild("Wheels")
	if not folder then
		warn("[DragDrive] в машине нет папки Wheels — управление невозможно")
		return nil
	end
	local cfg = tune.Config or "RWD"
	local list = {}
	for _, part in folder:GetChildren() do
		if part:IsA("BasePart") and (part.Name == "FL" or part.Name == "FR"
			or part.Name == "RL" or part.Name == "RR") then
			local isFront = string.find(part.Name, "F") ~= nil
			local driven = (cfg == "AWD")
				or (cfg == "FWD" and isFront)
				or (cfg == "RWD" and not isFront)
			local av = part:FindFirstChild("#AV")
			local bv = part:FindFirstChild("#BV")
			if av then
				table.insert(list, {
					part = part,
					av = av,
					bv = bv,
					driven = driven,
					radius = math.max(part.Size.Y, 0.1) / 2,
				})
			end
		end
	end
	if #list == 0 then
		warn("[DragDrive] не нашёл ни одного хинжа #AV — управление невозможно")
		return nil
	end
	return list
end

local function attach(carModel)
	local tuneModule = carModel:FindFirstChild("A-Chassis Tune", true)
	if not tuneModule then
		warn("[DragDrive] в машине нет модуля A-Chassis Tune")
		return
	end
	local ok, tune = pcall(require, tuneModule)
	if not ok or type(tune) ~= "table" then
		warn("[DragDrive] Tune не читается: " .. tostring(tune))
		return
	end

	engine = engineSpec(tune)
	ratios = (type(tune.GearRatios) == "table") and tune.GearRatios or nil
	wheels = collectWheels(carModel, tune)
	if not wheels then return end

	refPart = carModel:FindFirstChild("DriveSeat")
		or carModel:FindFirstChild("Body")
		or firstOfClass(carModel, "BasePart")

	gear = 1
	rpm = engine.idleRpm
	reversing = false
	car = carModel
	print(("[DragDrive] машина готова: %d передач, привод %s, отсечка %d")
		:format(engine.gearCount, tostring(tune.Config or "RWD"), engine.redline))
end

local function detach()
	car = nil
	wheels = nil
	engine = nil
	refPart = nil
end

local function gearRatio(g)
	if ratios and type(ratios[g]) == "number" then return ratios[g] end
	-- запасная коробка, если в Tune нет таблицы передач
	local fallback = { [1] = 3.2, [2] = 2.1, [3] = 1.55, [4] = 1.2, [5] = 0.95, [-1] = 3.2 }
	return fallback[g] or 1
end

local function forwardSpeed()
	if not refPart or not refPart.Parent then return 0 end
	local v = refPart.AssemblyLinearVelocity
	return -refPart.CFrame.LookVector:Dot(v) -- вперёд по -Z модели
end

-- Педали: W/СтрелкаВверх — газ, S/Вниз — тормоз/назад,
-- M — авто/ручная, LeftShift — вверх, LeftControl — вниз (в ручной).
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	local k = input.KeyCode
	if k == Enum.KeyCode.M then
		mode = (mode == "Auto") and "Manual" or "Auto"
	elseif k == Enum.KeyCode.LeftShift and mode == "Manual" then
		if gear < (engine and engine.gearCount or 1) then gear = gear + 1 end
	elseif k == Enum.KeyCode.LeftControl and mode == "Manual" then
		if gear > 1 then gear = gear - 1 end
	end
end)

local hud
local function makeHud()
	local gui = Instance.new("ScreenGui")
	gui.Name = "DriveHud"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")
	hud = Instance.new("TextLabel")
	hud.Size = UDim2.new(0, 300, 0, 26)
	hud.Position = UDim2.new(0, 12, 0, 10)
	hud.BackgroundTransparency = 1
	hud.Font = Enum.Font.Code
	hud.TextSize = 18
	hud.TextColor3 = Color3.fromRGB(235, 240, 245)
	hud.TextXAlignment = Enum.TextXAlignment.Left
	hud.Text = ""
	hud.Parent = gui
end

local hudClock = 0

RunService.Heartbeat:Connect(function(dt)
	-- педали каждый кадр
	throttle = (UserInputService:IsKeyDown(Enum.KeyCode.W)
		or UserInputService:IsKeyDown(Enum.KeyCode.Up)) and 1 or 0
	brake = (UserInputService:IsKeyDown(Enum.KeyCode.S)
		or UserInputService:IsKeyDown(Enum.KeyCode.Down)) and 1 or 0

	if not car or not car.Parent or not wheels or not engine then return end

	local speed = forwardSpeed()

	-- реверс: стоим и держим тормоз → задний ход; газ — снова вперёд
	if reversing then
		if throttle > 0 and speed > -1 then reversing = false end
	elseif speed < 1.5 and brake > 0 and throttle == 0 then
		reversing = true
	end

	local dir = reversing and -1 or 1
	local ratio = gearRatio(reversing and -1 or gear)

	-- обороты: от скорости колеса через передачу; на месте — холостые
	local wheelRPS = 0
	local drivenAny = false
	for _, w in wheels do
		if w.driven then
			wheelRPS = wheelRPS + math.abs(speed) / w.radius
			drivenAny = true
			break -- все колёса крутятся одинаково (прямо, без пробуксовки v0.2)
		end
	end
	if drivenAny then
		rpm = math.max(engine.idleRpm, Drivetrain.rpmFromWheel(wheelRPS, ratio, engine.finalDrive))
	else
		rpm = engine.idleRpm
	end
	rpm = math.min(rpm, engine.redline + 200)

	-- автомат переключает сам, ручной слушает Shift/Ctrl
	if mode == "Auto" and not reversing then
		gear = Drivetrain.autoShift(engine, gear, rpm)
	end

	-- привод и тормоза на хинжи; в реверсе газом считается тормозная педаль S
	local gasInput = reversing and brake or throttle
	local drivenCount = 0
	for _, w in wheels do
		if w.driven then drivenCount = drivenCount + 1 end
	end
	local perWheel = Drivetrain.wheelTorque(engine, rpm, ratio, drivenCount,
		reversing and 0.5 or gasInput, 0.85)

	for _, w in wheels do
		if w.driven and gasInput > 0 then
			w.av.MotorMaxTorque = perWheel
			w.av.AngularVelocity = dir * 400 -- цель «в пол», момент режет разгон
		else
			w.av.MotorMaxTorque = 0
			w.av.AngularVelocity = 0
		end
		if w.bv then
			local hold = (gasInput == 0 and math.abs(speed) < 0.5) and 2500 or 0 -- анти-катание
			local stopPedal = reversing and throttle or brake
			w.bv.MotorMaxTorque = stopPedal * 4000 + hold
		end
	end

	-- HUD 10 раз/сек
	hudClock = hudClock + dt
	if hud and hudClock > 0.1 then
		hudClock = 0
		local kmh = math.abs(speed) * 3.6 / Config.Race.StudsPerMeter
		local gearText = reversing and "R" or tostring(gear)
		hud.Text = ("%s  %d RPM  %d км/ч  [%s]")
			:format(gearText, rpm, kmh, mode)
	end
end)

-- следим за появлением/исчезновением нашей машины
local raceFolder = workspace:WaitForChild("Scene"):WaitForChild("Race")
local function onChild(child)
	if child.Name == "PlayerCar" and child:IsA("Model") then
		-- даём серверу поставить машину на место
		task.delay(0.5, function()
			if child.Parent then attach(child) end
		end)
	end
end
raceFolder.ChildAdded:Connect(onChild)
for _, c in raceFolder:GetChildren() do onChild(c) end

function Drive.start() end

return Drive
