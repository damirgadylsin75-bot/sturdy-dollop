-- CarService 2D: машина = кузов-пластина с картинкой + два колеса-цилиндра
-- на мотор-хинжах (ось X — к камере, в профиль видно круг). Всё строим сами,
-- никаких чужих моделей и скриптов. Физика на сервере. Плоскость держим
-- жёстко: скорость по X и вращения Y/Z гасим каждый тик — клюёт носом и
-- встаёт на дыды (вращение вокруг X), но влево-вправо не уплывает и не
-- крутится к камерой боком.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.config)
local Drivetrain = require(ReplicatedStorage.Shared.drivetrain)

local CarService = {}

local C = Config.Car2D
local E = Config.Engine

local cars = {} -- [model] = состояние (трансмиссия, педали, полоса)
local raceParent = workspace

-- Спрайт на деталь: SurfaceGui + ImageLabel (ScaleType=Fit) — картинка
-- ложится ВСЕГДА ЦЕЛИКОМ, без мозаики из повторов, с правильной пропорцией.
local function applyArt(part, imageId)
	if imageId == nil or imageId == "" then return end
	for _, face in { Enum.NormalId.Right, Enum.NormalId.Left } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 50
		gui.Parent = part
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Size = UDim2.fromScale(1, 1)
		img.ScaleType = Enum.ScaleType.Fit
		img.Image = imageId
		img.Parent = gui
	end
end

-- Сборка машины. cf — CFrame кузова (центр пластины). laneX — фиксация по X.
function CarService.buildCar(name, cf, isAI, laneX, parent)
	local model = Instance.new("Model")
	model.Name = name

	local bodyArt = isAI and Config.Art.AIBody or Config.Art.PlayerBody
	local wheelArt = isAI and Config.Art.AIWheel or Config.Art.PlayerWheel
	local bodyColor = isAI and Config.color("Car2") or Config.color("Car1")

	local base = Instance.new("Part")
	base.Name = "Body"
	base.Size = Vector3.new(C.BodyThickness, C.BodyHeight, C.BodyLength)
	base.Color = bodyColor
	base.CanCollide = false
	base.CustomPhysicalProperties = PhysicalProperties.new(C.BodyDensity, 0.3, 0.5)
	base.CFrame = cf
	base.Parent = model
	applyArt(base, bodyArt)

	local wheels = {}
	local defs = {
		{ n = "Front", z = C.FrontAxleZ, driven = false },
		{ n = "Rear", z = C.RearAxleZ, driven = true },
	}
	for _, def in defs do
		local w = Instance.new("Part")
		w.Name = def.n .. "Wheel"
		w.Shape = Enum.PartType.Cylinder
		w.Size = Vector3.new(C.WheelWidth, C.WheelRadius * 2, C.WheelRadius * 2)
		w.Color = Color3.fromRGB(24, 24, 27)
		w.CustomPhysicalProperties = PhysicalProperties.new(C.WheelDensity, C.WheelFriction, 0.4)
		w.CanCollide = true
		w.CFrame = cf * CFrame.new(0, -C.BodyHeight / 2, def.z)
		w.Parent = model
		applyArt(w, wheelArt)

		-- спица-заглушка: видно, как колесо крутится (пока нет картинок)
		if wheelArt == nil or wheelArt == "" then
			local hub = Instance.new("Part")
			hub.Name = "Hub"
			hub.Size = Vector3.new(0.12, C.WheelRadius * 1.1, 0.5)
			hub.Color = Color3.fromRGB(205, 210, 220)
			hub.CanCollide = false
			hub.Massless = true
			hub.CFrame = w.CFrame * CFrame.new(C.WheelWidth / 2 + 0.07, 0, 0)
			hub.Parent = model
			local hw = Instance.new("WeldConstraint")
			hw.Part0 = hub
			hw.Part1 = w
			hw.Parent = hub
		end

		local a0 = Instance.new("Attachment")
		a0.CFrame = CFrame.new(0, -C.BodyHeight / 2, def.z)
		a0.Parent = base
		local a1 = Instance.new("Attachment")
		a1.Parent = w
		local h = Instance.new("HingeConstraint")
		h.Name = def.n .. "Axle"
		h.Attachment0 = a0
		h.Attachment1 = a1
		h.ActuatorType = Enum.ActuatorType.Motor
		h.MotorMaxTorque = 0
		h.AngularVelocity = 0
		h.Parent = w

		wheels[def.n] = { part = w, hinge = h, driven = def.driven }
	end

	model.PrimaryPart = base
	model.Parent = parent or raceParent

	local st = {
		car = model,
		base = base,
		wheels = wheels,
		laneX = laneX or 0,
		isAI = isAI,
		engine = Config.engineSpec(),
		gear = 1,
		rpm = E.IdleRPM,
		mode = isAI and "Auto" or "Auto",
		gas = 0,
		brake = 0,
		green = false,
		dq = false,
		finished = false,
		pubClock = 0,
	}
	cars[model] = st
	return model, st
end

local function gearRatio(g)
	return E.GearRatios[g] or 1
end

-- Один шаг физики одной машины (сервер, каждый Heartbeat)
local function stepCar(st, dt)
	local base = st.base
	if not base.Parent then return end

	local gas = st.gas
	local brake = st.brake
	if not st.green or st.dq then
		gas = 0 -- до зелёного и после фальстарта тяги нет
	end

	local speed = -base.CFrame.LookVector:Dot(base.AssemblyLinearVelocity)
	local ratio = gearRatio(st.gear) * E.FinalDrive

	-- обороты из скорости колеса (пробуксовку не моделируем — её даёт физика)
	local wheelOmega = math.abs(speed) / C.WheelRadius
	st.rpm = math.max(st.engine.idleRpm, wheelOmega * ratio * 9.5493)
	st.rpm = math.min(st.rpm, st.engine.redline + 200)

	if st.mode == "Auto" then
		st.gear = Drivetrain.autoShift(st.engine, st.gear, st.rpm)
	end

	local tq = Drivetrain.wheelTorque(st.engine, st.rpm, ratio, 1, gas, 0.9)
		* E.TorqueScale

	for _, w in pairs(st.wheels) do
		local h = w.hinge
		if brake > 0 then
			h.AngularVelocity = 0
			h.MotorMaxTorque = C.BrakeTorque
		elseif gas > 0 and w.driven then
			h.AngularVelocity = E.DirSign * 300
			h.MotorMaxTorque = tq
		elseif w.driven then
			h.AngularVelocity = 0
			h.MotorMaxTorque = math.abs(speed) < 0.5 and C.HoldTorque or 0
		else
			h.AngularVelocity = 0
			h.MotorMaxTorque = 0 -- переднее крутится свободно
		end
	end

	-- держим 2D: гасим боковую скорость и повороты, кроме тангажа (X)
	local v = base.AssemblyLinearVelocity
	base.AssemblyLinearVelocity = Vector3.new(0, v.Y, v.Z)
	local av = base.AssemblyAngularVelocity
	base.AssemblyAngularVelocity = Vector3.new(av.X, 0, 0)

	-- аэросопротивление
	if v.Magnitude > 1 then
		base:ApplyImpulse(-v.Unit * (v.Magnitude * v.Magnitude * C.Drag)
			* base.AssemblyMass * dt)
	end

	-- машина не уплывает со своей полосы по X
	local p = base.Position
	if math.abs(p.X - st.laneX) > 0.2 then
		base.CFrame = base.CFrame - Vector3.new(p.X - st.laneX, 0, 0)
	end

	-- приборы для клиента (10 раз/сек)
	st.pubClock = st.pubClock + dt
	if st.pubClock > 0.1 then
		st.pubClock = 0
		st.car:SetAttribute("RPM", math.floor(st.rpm))
		st.car:SetAttribute("Gear", st.gear)
		st.car:SetAttribute("Kmh", math.floor(math.abs(speed) * 3.6 / Config.Race.StudsPerMeter))
	end
end

RunService.Heartbeat:Connect(function(dt)
	for _, st in pairs(cars) do
		stepCar(st, dt)
	end
end)

function CarService.setPedal(model, gas, brake)
	local st = cars[model]
	if not st then return end
	st.gas = gas and 1 or 0
	st.brake = brake and 1 or 0
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

function CarService.getState(model)
	return cars[model]
end

function CarService.baseOf(model)
	local st = cars[model]
	return st and st.base or nil
end

function CarService.removeAll()
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

function CarService.setParent(parent)
	raceParent = parent or workspace
end

return CarService
