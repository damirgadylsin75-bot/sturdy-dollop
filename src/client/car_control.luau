-- DragDrive: наша система управления. Модель может быть «витринной» (без
-- физики) — сервер при спавне добавляет ей мотор-хинжи колёс (#AV), а этот
-- скрипт крутит их по кривой момента из Tune: авто/ручная коробка, отсечка,
-- задний ход. Ручная даёт выгоду только через пик кривой — без бонусов.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.config)
local Drivetrain = require(ReplicatedStorage.Shared.drivetrain)

local player = Players.LocalPlayer

local Drive = {}

local car -- модель PlayerCar
local wheels -- { {part=, av=, driven=, radius=} }
local drivenCount = 0
local engine -- спецификация для Drivetrain
local ratios -- таблица передач из Tune
local refPart -- по чему меряем скорость
local rpm, gear = 0, 1
local reversing = false
local mode = "Auto" -- "Auto" | "Manual"
local throttle, brake = 0, 0
local hud, hudClock = nil, 0
local native = false -- родное шасси: рулит его Drive, мы только HUD
local values -- родной Values (для HUD в native-режиме)

local TSCALE = Config.Tuning.DriveTorqueScale or 4

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
		warn("[DragDrive] в машине нет папки Wheels")
		return nil
	end
	local cfg = tune.Config or "RWD"
	local list = {}
	for _, part in folder:GetChildren() do
		if part:IsA("BasePart") and (part.Name == "FL" or part.Name == "FR"
			or part.Name == "RL" or part.Name == "RR") then
			local av = part:FindFirstChild("#AV")
			if av then
				local isFront = string.find(part.Name, "F") ~= nil
				local driven = (cfg == "AWD")
					or (cfg == "FWD" and isFront)
					or (cfg == "RWD" and not isFront)
				table.insert(list, {
					part = part,
					av = av,
					driven = driven,
					radius = math.max(math.min(part.Size.Y, part.Size.Z) / 2, 0.1),
				})
			end
		end
	end
	if #list == 0 then
		warn("[DragDrive] мотор-хинжи не найдены (сервер не создал #AV?)")
		return nil
	end
	return list
end

local function attach(carModel)
	if carModel:GetAttribute("NativeChassis") then
		-- родное шасси: педали/передачи делает ЕГО Drive, мы не вмешиваемся
		native = true
		car = carModel
		values = carModel:FindFirstChild("Values")
		makeHud()
		print("[DragDrive] родное шасси: управление — его Drive, HUD из его Values")
		return
	end

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

	drivenCount = 0
	for _, w in wheels do
		if w.driven then drivenCount = drivenCount + 1 end
	end

	refPart = carModel.PrimaryPart
		or carModel:FindFirstChild("Body")
		or (wheels[1] and wheels[1].part)

	gear = 1
	rpm = engine.idleRpm
	reversing = false
	car = carModel
	print(("[DragDrive] готов: %d передач, привод %s, отсечка %d, моторов %d (ведущих %d)")
		:format(engine.gearCount, tostring(tune.Config or "RWD"), engine.redline, #wheels, drivenCount))
end

local function gearRatio(g)
	if ratios and type(ratios[g]) == "number" then return ratios[g] end
	local fallback = { [1] = 3.2, [2] = 2.1, [3] = 1.55, [4] = 1.2, [5] = 0.95, [-1] = 3.2 }
	return fallback[g] or 1
end

local function forwardSpeed()
	if not refPart or not refPart.Parent then return 0 end
	local v = refPart.AssemblyLinearVelocity
	local look = car.PrimaryPart and car.PrimaryPart.CFrame.LookVector
		or (refPart.CFrame.LookVector)
	return -look:Dot(v)
end

-- W/СтрелкаВверх — газ, S/Вниз — тормоз (и газ заднего хода на месте),
-- M — авто/ручная, LeftShift/LeftControl — передачи в ручной.
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

RunService.Heartbeat:Connect(function(dt)
	throttle = (UserInputService:IsKeyDown(Enum.KeyCode.W)
		or UserInputService:IsKeyDown(Enum.KeyCode.Up)) and 1 or 0
	brake = (UserInputService:IsKeyDown(Enum.KeyCode.S)
		or UserInputService:IsKeyDown(Enum.KeyCode.Down)) and 1 or 0

	if not car or not car.Parent then
		return
	end

	-- родное шасси: только приборы из его Values
	if native then
		hudClock = hudClock + dt
		if hud and hudClock > 0.1 then
			hudClock = 0
			local function num(name)
				local v = values and values:FindFirstChild(name)
				if v and (v:IsA("NumberValue") or v:IsA("IntValue")) then return v.Value end
				return nil
			end
			local rpmN = num("RPM") or 0
			local gearN = num("Gear") or 0
			local kmh = math.abs(num("Velocity") or 0) * 3.6 / Config.Race.StudsPerMeter
			hud.Text = ("%s  %d RPM  %d км/ч  [stock]"):format(
				gearN < 0 and "R" or tostring(gearN), rpmN, kmh)
		end
		return
	end

	if not wheels or not engine then
		return
	end

	local speed = forwardSpeed()

	if reversing then
		if throttle > 0 and speed > -1 then reversing = false end
	elseif speed < 1.5 and brake > 0 and throttle == 0 then
		reversing = true
	end

	local dir = reversing and -1 or 1
	local ratio = gearRatio(reversing and -1 or gear)

	-- обороты из скорости через передачу; на месте — холостые
	local wheelRPS = 0
	for _, w in wheels do
		if w.driven then
			wheelRPS = math.abs(speed) / w.radius
			break
		end
	end
	rpm = math.max(engine.idleRpm,
		Drivetrain.rpmFromWheel(wheelRPS, ratio, engine.finalDrive))
	rpm = math.min(rpm, engine.redline + 200)

	if mode == "Auto" and not reversing then
		gear = Drivetrain.autoShift(engine, gear, rpm)
	end

	-- педали: в реверсе газ = S, стоп = W
	local gasInput = reversing and brake or throttle
	local stopPedal = reversing and throttle or brake

	-- момент на ведущее колесо по кривой, с масштабом массы модели
	local perWheel = Drivetrain.wheelTorque(engine, rpm, ratio,
		math.max(drivenCount, 1), gasInput, 0.85) * TSCALE
	local brakeTq = 4000 * TSCALE

	for _, w in wheels do
		if w.driven and gasInput > 0 then
			w.av.AngularVelocity = dir * 400
			w.av.MotorMaxTorque = perWheel
		elseif stopPedal > 0 then
			w.av.AngularVelocity = 0
			w.av.MotorMaxTorque = brakeTq
		elseif math.abs(speed) < 0.5 then
			w.av.AngularVelocity = 0
			w.av.MotorMaxTorque = 1200 * TSCALE -- анти-катание на месте
		else
			w.av.MotorMaxTorque = 0 -- свободный крен
		end
	end

	hudClock = hudClock + dt
	if hud and hudClock > 0.1 then
		hudClock = 0
		local kmh = math.abs(speed) * 3.6 / Config.Race.StudsPerMeter
		local gearText = reversing and "R" or tostring(gear)
		hud.Text = ("%s  %d RPM  %d км/ч  [%s]")
			:format(gearText, rpm, kmh, mode)
	end
end)

local raceFolder = workspace:WaitForChild("Scene"):WaitForChild("Race")
local function onChild(child)
	if child.Name == "PlayerCar" and child:IsA("Model") then
		-- даём серверу доработать (физика/владелец)
		task.delay(0.8, function()
			if child.Parent then attach(child) end
		end)
	end
end
raceFolder.ChildAdded:Connect(onChild)
for _, c in raceFolder:GetChildren() do onChild(c) end

function Drive.start() end

return Drive
