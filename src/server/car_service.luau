-- CarService: ШАССИ ПИШЕМ САМИ (рама, 4 колеса на мотор-хинжах, сиденье,
-- стабилизатор) и привариваем КУЗОВ ПОЛЬЗОВАТЕЛЯ сверху. Родные скрипты
-- модели не участвуют (в копии снимаются), оригинал в Workspace не трогается.
-- Физику держит сервер, игрок садится в DriverSeat и не может встать —
-- газ/тормоз работают через родной VehicleSeat (W/S), ходьбы нет.

local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.config)
local Drivetrain = require(ReplicatedStorage.Shared.drivetrain)

local CarService = {}

local TUNE_NAME = "A-Chassis Tune"
local TEMPLATE_NAME = "DefaultCar"
local TAG = "[Drag " .. Config.Version .. "]"
local CH = Config.Chassis
local E = Config.Engine

local templates = ServerStorage:FindFirstChild("CarTemplates")
if not templates then
	templates = Instance.new("Folder")
	templates.Name = "CarTemplates"
	templates.Parent = ServerStorage
end

local state, raceFolder
local cars = {} -- [модель] = стейт трансмиссии (игрок и ИИ одинаковы)

local function isCarModel(model)
	if not model or not model:IsA("Model") then return false end
	if model:IsDescendantOf(templates) then return false end
	if raceFolder and model:IsDescendantOf(raceFolder) then return false end
	return model:FindFirstChild(TUNE_NAME, true) ~= nil
		or model:FindFirstChild("DriveSeat", true) ~= nil
end

-- ===== СТРОИМ ШАССИ =====
-- Ось цилиндра-колеса = локальный X. Мы НЕ поворачиваем колесо относительно
-- рамы → ось смотрит влево-вправо → колесо катится ровно вперёд. Это и есть
-- фикс «колёса вправо-влево»: раньше ось брали из чужих моделей.
local function buildChassis(cf)
	local model = Instance.new("Model")
	model.Name = "Chassis"

	local base = Instance.new("Part")
	base.Name = "Frame"
	base.Size = Vector3.new(CH.Width, CH.Height, CH.Length)
	local groundY = cf.Position.Y
	base.CFrame = cf * CFrame.new(0, CH.WheelDiameter / 2 + CH.Clearance + CH.Height / 2, 0)
	base.CanCollide = true
	base.Parent = model

	local wheelY = -(CH.WheelDiameter / 2 + CH.Clearance + CH.Height / 2)
	local halfL = CH.Length / 2
	local halfW = CH.Width / 2
	local wheelDefs = {
		{ name = "FL", x = -halfW - 0.2, z = -halfL + 3, driven = false },
		{ name = "FR", x = halfW + 0.2, z = -halfL + 3, driven = false },
		{ name = "RL", x = -halfW - 0.2, z = halfL - 3, driven = true },
		{ name = "RR", x = halfW + 0.2, z = halfL - 3, driven = true },
	}

	local wheels = {}
	for _, def in wheelDefs do
		local w = Instance.new("Part")
		w.Name = def.name
		w.Shape = Enum.PartType.Cylinder
		w.Size = Vector3.new(CH.WheelWidth, CH.WheelDiameter, CH.WheelDiameter)
		w.CFrame = base.CFrame * CFrame.new(def.x, wheelY, def.z)
		w.CustomPhysicalProperties = PhysicalProperties.new(3, 1.5, 0.3)
		w.Parent = model

		local a0 = Instance.new("Attachment")
		a0.CFrame = CFrame.new(def.x, wheelY, def.z)
		a0.Parent = base
		local a1 = Instance.new("Attachment")
		a1.Parent = w
		local h = Instance.new("HingeConstraint")
		h.Name = def.name .. "Motor"
		h.Attachment0 = a0
		h.Attachment1 = a1
		h.ActuatorType = Enum.ActuatorType.Motor
		h.MotorMaxTorque = 0
		h.AngularVelocity = 0
		h.Parent = w

		local weld = Instance.new("WeldConstraint") -- колесо на своей оси
		weld.Part0 = w
		weld.Part1 = base
		weld.Parent = w

		wheels[def.name] = { part = w, hinge = h, driven = def.driven }
	end

	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(2, 0.4, 2)
	seat.CFrame = base.CFrame * CFrame.new(0, CH.Height / 2 + 0.3, 1)
	seat.HeadsUpDisplay = false
	seat.MaxSpeed = 0 -- мотор сиденья не нужен, газ делаем сами
	seat.CanCollide = false
	seat.Parent = model
	local seatWeld = Instance.new("WeldConstraint")
	seatWeld.Part0 = seat
	seatWeld.Part1 = base
	seatWeld.Parent = seat

	-- стабилизатор: драг — прямо и без переворотов
	local af = Instance.new("Attachment")
	af.Parent = base
	local ao = Instance.new("AlignOrientation")
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = af
	ao.MaxTorque = CH.StabilizeTorque
	ao.MaxAngularVelocity = 20
	ao.Responsiveness = 8
	ao.CFrame = base.CFrame.Rotation
	ao.Parent = base

	return model, base, wheels, seat
end

-- ===== КУЗОВ ПОЛЬЗОВАТЕЛЯ =====
-- В копии: чужие скрипты снимаются (рулим мы), констрейнты снимаются (шасси
-- теперь наше), колёса модели прячутся (наши виднее), всё остальное
-- приваривается к раме. Оригинал в Workspace нетронут.
local function addBody(chassisModel, base, bodyModel)
	local hidden = 0
	for _, d in bodyModel:GetDescendants() do
		if d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		elseif d:IsA("HingeConstraint") or d:IsA("PrismaticConstraint")
			or d:IsA("SpringConstraint") or d:IsA("BallSocketConstraint")
			or d:IsA("CylindricalConstraint") then
			d:Destroy()
		end
	end

	-- нос кузова по его водительскому сиденью (в системе координат модели)
	local theta = 0
	local seat = bodyModel:FindFirstChild("DriveSeat", true)
	if seat and seat:IsA("BasePart") then
		local rel = bodyModel:GetPivot():ToObjectSpace(seat.CFrame).LookVector
		local flat = Vector3.new(rel.X, 0, rel.Z)
		if flat.Magnitude > 0.05 then
			theta = math.atan2(flat.Unit.X, -flat.Unit.Z)
		end
	end

	bodyModel:PivotTo(base.CFrame
		* CFrame.new(0, CH.Height / 2 + CH.BodyLift, 0)
		* CFrame.Angles(0, theta, 0))

	for _, p in bodyModel:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.CanCollide = false
			p.Massless = true
			-- старые колёса модели прячем: теперь колёса наши
			if p.Name == "FL" or p.Name == "FR" or p.Name == "RL" or p.Name == "RR" then
				p.Transparency = 1
				hidden = hidden + 1
			end
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = p
			weld.Part1 = base
			weld.Parent = p
		end
	end
	return hidden
end

-- ===== ТРАНСМИССИЯ (общая для игрока и ИИ) =====
local function newCarState(car, base, wheels, seat, isAI)
	return {
		car = car, base = base, wheels = wheels, seat = seat,
		isAI = isAI,
		engine = Config.engineSpec(),
		gear = 1, rpm = E.IdleRPM, mode = "Auto",
		green = false, dq = false, finished = false,
		finishTime = nil, reaction = nil,
		aiThrottle = 0, pubClock = 0,
	}
end

local function gearRatio(g)
	if g == -1 then return E.GearRatios[1] end
	return E.GearRatios[g] or 1
end

-- один шаг физики одной машины (сервер, каждый Heartbeat)
local function stepCar(st, dt)
	local base = st.base
	if not base.Parent then return end

	local gas, brakeIn
	if st.isAI then
		gas, brakeIn = st.aiThrottle, 0
	else
		local t = st.seat.Throttle
		gas, brakeIn = math.max(0, t), math.max(0, -t)
	end
	if st.dq and not st.green then
		gas = 0 -- фальстарт: до зелёного не едет
	end

	local speed = -base.CFrame.LookVector:Dot(base.AssemblyLinearVelocity)
	local radius = CH.WheelDiameter / 2
	local ratio = gearRatio(st.gear)

	st.rpm = math.max(st.engine.idleRpm,
		Drivetrain.rpmFromWheel(math.abs(speed) / radius, ratio, st.engine.finalDrive))
	st.rpm = math.min(st.rpm, st.engine.redline + 200)

	if st.mode == "Auto" then
		st.gear = Drivetrain.autoShift(st.engine, st.gear, st.rpm)
	end

	local perWheel = Drivetrain.wheelTorque(st.engine, st.rpm, ratio, 2,
		gas, 0.85) * E.TorqueScale

	for _, w in pairs(st.wheels) do
		local h = w.hinge
		if brakeIn > 0 then
			h.AngularVelocity = 0
			h.MotorMaxTorque = CH.BrakeTorque
		elseif gas > 0 and w.driven then
			h.AngularVelocity = CH.DirSign * 400
			h.MotorMaxTorque = perWheel
		elseif gas > 0 then
			h.AngularVelocity = 0
			h.MotorMaxTorque = 0 -- передние свободно крутятся
		elseif math.abs(speed) < 0.5 then
			h.AngularVelocity = 0
			h.MotorMaxTorque = CH.HoldTorque
		else
			h.AngularVelocity = 0
			h.MotorMaxTorque = 0
		end
	end

	-- аэросопротивление: ограничивает максималку естественно
	local v = base.AssemblyLinearVelocity
	if v.Magnitude > 1 then
		base:ApplyImpulse(-v.Unit * (v.Magnitude * v.Magnitude * CH.Drag)
			* base.AssemblyMass * dt)
	end

	st.pubClock = st.pubClock + dt
	if st.pubClock > 0.1 then
		st.pubClock = 0
		local kmh = math.abs(speed) * 3.6 / Config.Race.StudsPerMeter
		st.car:SetAttribute("RPM", math.floor(st.rpm))
		st.car:SetAttribute("Gear", st.gear)
		st.car:SetAttribute("Kmh", math.floor(kmh))
	end
end

RunService.Heartbeat:Connect(function(dt)
	for _, st in pairs(cars) do
		stepCar(st, dt)
	end
end)

-- ===== API =====

-- Захват кузова: переносим модель в шаблоны как есть (внутри сессии).
function CarService.absorb(model)
	if not isCarModel(model) then return end
	if templates:FindFirstChild(TEMPLATE_NAME) then
		warn(("%s кузов уже есть — «%s» не трогаю (замена: удали DefaultCar в ServerStorage)")
			:format(TAG, model.Name))
		return
	end
	local originalName = model.Name
	model.Name = TEMPLATE_NAME
	model.Parent = templates
	state:SetAttribute("CarStatus", "Ready")
	state:SetAttribute("CarName", originalName)
	print(("%s кузов захвачен: «%s». Шасси построю сам."):format(TAG, originalName))
end

-- Полная сборка: наше шасси + кузов пользователя. Возвращает стейт.
function CarService.buildCar(name, cf, isAI)
	local template = templates:FindFirstChild(TEMPLATE_NAME)
	local model, base, wheels, seat = buildChassis(cf)
	model.Name = name
	local hidden = nil
	if template then
		local body = template:Clone()
		hidden = addBody(model, base, body)
		body.Parent = model
	else
		warn(("%s кузова нет — машина будет голой рамой (закинь модель в Workspace)")
			:format(TAG))
	end
	local st = newCarState(model, base, wheels, seat, isAI)
	cars[model] = st
	model.Parent = raceFolder or workspace
	print(("%s собрана: %s (шасси наше, колёс 4, скрыто старых колёс: %s)")
		:format(TAG, name, tostring(hidden)))
	return model, st
end

function CarService.despawnAll()
	for model in pairs(cars) do
		if model.Parent then model:Destroy() end
	end
	cars = {}
end

function CarService.removeCar(model)
	if model and cars[model] then
		cars[model] = nil
		if model.Parent then model:Destroy() end
	end
end

function CarService.getCarState(model)
	return cars[model]
end

function CarService.setGear(model, action)
	local st = cars[model]
	if not st then return end
	if action == "mode" then
		st.mode = (st.mode == "Auto") and "Manual" or "Auto"
	elseif action == "up" and st.mode == "Manual" then
		if st.gear < st.engine.gearCount then st.gear = st.gear + 1 end
	elseif action == "down" and st.mode == "Manual" then
		if st.gear > 1 then st.gear = st.gear - 1 end
	end
end

-- Посадка игрока без ходьбы: персонаж появляется сразу в сиденье, прыжок
-- отключён — встать нельзя. (Подсказка пользователя — принято.)
function CarService.seatPlayer(plr, car)
	local seat = car and car:FindFirstChild("DriverSeat", true)
	if not seat then return end
	local char = plr.Character
	if not char then
		pcall(function()
			plr:LoadCharacter()
		end)
		char = plr.Character
	end
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	pcall(function()
		hum.JumpPower = 0
	end)
	pcall(function()
		hum.JumpHeight = 0
	end)
	if not hum.SeatPart or hum.SeatPart ~= seat then
		seat:Sit(hum)
	end
end

function CarService.startup(stateRef, raceFolderRef)
	state = stateRef
	raceFolder = raceFolderRef

	for _, d in workspace:GetDescendants() do
		if d:IsA("ModuleScript") and d.Name == TUNE_NAME and isCarModel(d.Parent) then
			CarService.absorb(d.Parent)
			break
		elseif d:IsA("BasePart") and d.Name == "DriveSeat" and d.Parent:IsA("Model")
			and d.Parent.Parent == workspace then
			CarService.absorb(d.Parent)
			break
		end
	end

	workspace.DescendantAdded:Connect(function(d)
		if (d:IsA("ModuleScript") and d.Name == TUNE_NAME)
			or (d:IsA("BasePart") and d.Name == "DriveSeat" and d.Parent
				and d.Parent.Parent == workspace) then
			task.defer(function()
				local model = d.Parent
				while model and not model:IsA("Model") do
					model = model.Parent
				end
				CarService.absorb(model)
			end)
		end
	end)

	if not templates:FindFirstChild(TEMPLATE_NAME) then
		state:SetAttribute("CarStatus", "Waiting")
		print(("%s жду кузов: закинь модель машины в Workspace (шасси построю сам)")
			:format(TAG))
	end
end

return CarService
