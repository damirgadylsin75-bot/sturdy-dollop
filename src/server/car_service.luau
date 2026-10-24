-- CarService: ловит A-Chassis-машину, брошенную пользователем в Workspace,
-- держит её как шаблон и спавнит копии на старт. Модель НЕ трогаем ВООБЩЕ:
-- её родной стек A-Chassis (Initialize сваривает, Drive управляет) сам
-- отвечает за сборку и езду. Наше дело — спавн, владелец физики, стейт.

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.config)

local CarService = {}

local TUNE_NAME = "A-Chassis Tune"
local TEMPLATE_NAME = "DefaultCar"

local TAG = "[Drag " .. Config.Version .. "]"

local templates = ServerStorage:FindFirstChild("CarTemplates")
if not templates then
	templates = Instance.new("Folder")
	templates.Name = "CarTemplates"
	templates.Parent = ServerStorage
end

local state -- GameState из ReplicatedStorage
local raceFolder -- workspace.Scene.Race
local currentCar -- текущая заспавненная машина игрока

local function isCarModel(model)
	if not model or not model:IsA("Model") then return false end
	if model:IsDescendantOf(templates) then return false end
	if raceFolder and model:IsDescendantOf(raceFolder) then return false end
	-- у A-Chassis машин модуль тюнинга лежит прямо в модели
	return model:FindFirstChild(TUNE_NAME, true) ~= nil
end

-- Перенести найденную модель в шаблоны (внутри сессии). Как есть.
function CarService.absorb(model)
	if not isCarModel(model) then return end
	if state:GetAttribute("CarStatus") == "Ready" then
		warn(("%s машина уже захвачена — «%s» не трогаю"):format(TAG, model.Name))
		return
	end

	local originalName = model.Name
	model.Name = TEMPLATE_NAME
	model.Parent = templates
	state:SetAttribute("CarStatus", "Ready")
	state:SetAttribute("CarName", originalName)
	print(("%s машина захвачена как есть: «%s» (родной стек A-Chassis работает).")
		:format(TAG, originalName))
end

-- Отдать физику машины игроку: без этого родной Drive (клиент) крутит
-- констрейнты вхолостую. Владение задаётся ТОЛЬКО на корнях сборок
-- (SetNetworkOwner на приваренных/заякоренных частях запрещён).
function CarService.setOwner(car, plr)
	if not car or not car.Parent or not plr then return end
	for _, p in car:GetDescendants() do
		if p:IsA("BasePart") and not p.Anchored and p:GetRootPart() == p then
			pcall(function()
				p:SetNetworkOwner(plr)
			end)
		end
	end
end

-- CarPhysics (встроено, чтобы не плодить файлы, которые Rojo не доносит
-- в живую сессию): витринную модель (держится якорями, физики нет)
-- превращает в физическую машину. НИЧЕГО не удаляет: декор приваривается
-- к корню, якоря снимаются, колёсам создаются мотор-хинжи (#AV), курс
-- держится ровно. Всё на КОПИИ при спавне — оригинал не тронут.
local WHEEL_NAMES = { FL = true, FR = true, RL = true, RR = true }

local function volume(p)
	return p.Size.X * p.Size.Y * p.Size.Z
end

local CarPhysics = {}


local WHEEL_NAMES = { FL = true, FR = true, RL = true, RR = true }

local function volume(p)
	return p.Size.X * p.Size.Y * p.Size.Z
end

function CarPhysics.build(car)
	local wheelsFolder = car:FindFirstChild("Wheels")

	-- привод из Tune (какие колёса ведущие)
	local config = "RWD"
	local tuneModule = car:FindFirstChild("A-Chassis Tune", true)
	if tuneModule then
		local ok, t = pcall(require, tuneModule)
		if ok and type(t) == "table" and t.Config then
			config = tostring(t.Config)
		end
	end

	local wheelParts, wheelDesc = {}, {}
	if wheelsFolder then
		for _, p in wheelsFolder:GetChildren() do
			if p:IsA("BasePart") and WHEEL_NAMES[p.Name] then
				wheelParts[p.Name] = p
				for _, d in p:GetDescendants() do
					wheelDesc[d] = true
				end
			end
		end
	end
	local function isWheel(d)
		return wheelParts[d.Name] == d or wheelDesc[d] == true
	end

	-- корень: PrimaryPart или самая большая не-колесо
	local root = car.PrimaryPart
	if not (root and root:IsA("BasePart")) or isWheel(root) then
		local best
		for _, d in car:GetDescendants() do
			if d:IsA("BasePart") and not isWheel(d) then
				if not best or volume(d) > volume(best) then best = d end
			end
		end
		root = best
	end
	if not root then
		return nil, "не нашёл корневую часть"
	end
	car.PrimaryPart = root

	-- сварить всё: декор — к корню, внутренности колеса — к своей ступице
	for _, d in car:GetDescendants() do
		if d:IsA("BasePart") then
			if wheelDesc[d] then
				local hub = d
				while hub.Parent and not wheelParts[hub.Name] do
					hub = hub.Parent
				end
				if hub ~= d and wheelParts[hub.Name] then
					local w = Instance.new("WeldConstraint")
					w.Part0 = d
					w.Part1 = hub
					w.Parent = d
				end
			elseif wheelParts[d.Name] ~= d and d ~= root then
				local w = Instance.new("WeldConstraint")
				w.Part0 = d
				w.Part1 = root
				w.Parent = d
			end
		end
	end

	-- якоря долой (всё сварено — не разлетится), декор без столкновений:
	-- машина едет на колёсах, а не брюхом
	for _, d in car:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			if not (wheelParts[d.Name] == d or wheelDesc[d]) then
				d.CanCollide = false
			end
		end
	end

	-- мотор-хинжи колёс: ось = X колеса (ось цилиндра)
	local created = {}
	for name, wp in pairs(wheelParts) do
		if not wp:IsA("MeshPart") then
			wp.Shape = Enum.PartType.Cylinder
		end
		local a0 = Instance.new("Attachment")
		a0.CFrame = root.CFrame:ToObjectSpace(wp.CFrame)
		a0.Parent = root
		local a1 = Instance.new("Attachment")
		a1.Parent = wp
		local h = Instance.new("HingeConstraint")
		h.Name = "#AV"
		h.Attachment0 = a0
		h.Attachment1 = a1
		h.ActuatorType = Enum.ActuatorType.Motor
		h.MotorMaxTorque = 0
		h.AngularVelocity = 0
		h.Parent = wp
		created[name] = h
	end

	-- держатель курса: не переворачивается и едет прямо (драг!)
	local af = Instance.new("Attachment")
	af.Parent = root
	local ao = Instance.new("AlignOrientation")
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = af
	ao.MaxTorque = 1e9
	ao.MaxAngularVelocity = 25
	ao.Responsiveness = 15
	ao.CFrame = root.CFrame.Rotation
	ao.Parent = root

	return {
		root = root,
		wheels = created,
		config = config,
	}
end


-- Спавн копии шаблона. tune — правки Tune до инициализации (v0.4: УОЗ).
function CarService.spawn(cf, ownerPlayer)
	local template = templates:FindFirstChild(TEMPLATE_NAME)
	if not template then
		state:SetAttribute("CarStatus", "Waiting")
		warn(("%s шаблона машины нет: закинь A-Chassis машину в Workspace (см. README)"):format(TAG))
		return nil
	end

	CarService.despawn()

	-- СПАВН: копия как есть + физическая начинка от CarPhysics (если модель
	-- витринная — сварка декора, мотор-хинжи колёс, держатель курса).
	local car = template:Clone()
	car.Name = "PlayerCar"
	car:PivotTo(cf)
	car.Parent = raceFolder

	local phys, physErr = CarPhysics.build(car)
	if phys then
		local n = 0
		for _ in pairs(phys.wheels) do n = n + 1 end
		print(("%s [physics] начинка готова: привод %s, моторов %d"):format(
			TAG, phys.config, n))
	else
		warn(("%s [physics] машину не оживить: %s"):format(TAG, tostring(physErr)))
	end

	car:SetAttribute("OwnerUserId", ownerPlayer and ownerPlayer.UserId or 0)
	currentCar = car

	-- глубокая диагностика: из чего машина и ЧЕМ она может ехать
	task.delay(1.2, function()
		if not car.Parent then return end
		local parts, anchored, welds = 0, 0, 0
		local hinges, prisms, springs, movers = {}, 0, 0, {}
		local wheelsInfo = {}
		local wf = car:FindFirstChild("Wheels")
		if wf then
			for _, w in wf:GetChildren() do
				local kids = {}
				for _, k in w:GetChildren() do
					table.insert(kids, k.Name .. ":" .. k.ClassName)
				end
				table.insert(wheelsInfo, ("%s[%s]{%s}"):format(
					w.Name, w.ClassName, table.concat(kids, " ")))
				for _, k in w:GetDescendants() do
					if k:IsA("HingeConstraint") then hinges[#hinges + 1] = k.Name end
					if k:IsA("BodyVelocity") or k:IsA("BodyAngularVelocity") or k:IsA("BodyGyro") then
						movers[k.ClassName] = (movers[k.ClassName] or 0) + 1
					end
				end
			end
		end
		for _, d in car:GetDescendants() do
			if d:IsA("BasePart") then
				parts = parts + 1
				if d.Anchored then anchored = anchored + 1 end
			end
			if d:IsA("WeldConstraint") or d:IsA("Weld") or d:IsA("Motor6D") then welds = welds + 1 end
			if d:IsA("HingeConstraint") then hinges[#hinges + 1] = d.Name end
			if d:IsA("PrismaticConstraint") then prisms = prisms + 1 end
			if d:IsA("SpringConstraint") then springs = springs + 1 end
			if d:IsA("BodyVelocity") or d:IsA("BodyAngularVelocity") or d:IsA("BodyGyro") then
				movers[d.ClassName] = (movers[d.ClassName] or 0) + 1
			end
		end
		local mv = {}
		for c, n in pairs(movers) do table.insert(mv, c .. "x" .. n) end
		table.sort(mv)
		print(("%s структура: частей %d (якорей %d), сварок %d, хинжей %d, призм %d, пружин %d, бодичаны[%s]")
			:format(TAG, parts, anchored, welds, #hinges, prisms, springs, table.concat(mv, ",")))
		print(("%s колёса: %s"):format(TAG, table.concat(wheelsInfo, "  ")))
	end)

	task.delay(0.4, function()
		if car.Parent then
			CarService.setOwner(car, ownerPlayer or Players:GetPlayerByUserId(car:GetAttribute("OwnerUserId") or 0))
		end
	end)
	return car
end

function CarService.despawn()
	if currentCar then
		currentCar:Destroy()
		currentCar = nil
	end
end

function CarService.getCurrent()
	return currentCar
end

function CarService.getTemplate()
	return templates:FindFirstChild(TEMPLATE_NAME)
end

function CarService.startup(stateRef, raceFolderRef)
	state = stateRef
	raceFolder = raceFolderRef

	-- машина, уже лежащая в Workspace при старте сервера
	for _, d in workspace:GetDescendants() do
		if d:IsA("ModuleScript") and d.Name == TUNE_NAME and isCarModel(d.Parent) then
			CarService.absorb(d.Parent)
			break
		end
	end

	-- или закинутая позже, прямо во время сессии
	workspace.DescendantAdded:Connect(function(d)
		if d:IsA("ModuleScript") and d.Name == TUNE_NAME then
			task.defer(function()
				CarService.absorb(d.Parent)
			end)
		end
	end)

	if state:GetAttribute("CarStatus") ~= "Ready" then
		state:SetAttribute("CarStatus", "Waiting")
		print(("%s жду машину: закинь A-Chassis модель в Workspace (см. README)"):format(TAG))
	end
end

return CarService
