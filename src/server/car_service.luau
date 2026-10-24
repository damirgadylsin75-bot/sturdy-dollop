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
-- констрейнты вхолостую. Вызывается с небольшой задержкой после спавна.
function CarService.setOwner(car, plr)
	if not car or not car.Parent or not plr then return end
	for _, p in car:GetDescendants() do
		if p:IsA("BasePart") and not p.Anchored then
			pcall(function()
				p:SetNetworkOwner(plr)
			end)
		end
	end
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

	-- Стоковый сценарий A-Chassis: модель в мире → её скрипты сами варят
	-- и ведут машину. Ничего не глушим, не анкируем, не перекручиваем.
	local car = template:Clone()
	car.Name = "PlayerCar"
	car.Parent = raceFolder
	car:PivotTo(cf)

	car:SetAttribute("OwnerUserId", ownerPlayer and ownerPlayer.UserId or 0)
	currentCar = car

	-- диагностика структуры (для интеграции ИИ/тюнинга на следующих шагах)
	task.delay(1.2, function()
		if not car.Parent then return end
		local parts, welds, hingeNames = 0, 0, {}
		local wheelsInfo = {}
		local wf = car:FindFirstChild("Wheels")
		if wf then
			for _, w in wf:GetChildren() do
				local av = w:FindFirstChild("#AV", true)
				table.insert(wheelsInfo, ("%s/%s%s"):format(w.Name, w.ClassName, av and "(#AV)" or ""))
			end
		end
		for _, d in car:GetDescendants() do
			if d:IsA("BasePart") then parts = parts + 1 end
			if d:IsA("WeldConstraint") or d:IsA("Weld") or d:IsA("Motor6D") then welds = welds + 1 end
			if d:IsA("HingeConstraint") then
				hingeNames[d.Name] = (hingeNames[d.Name] or 0) + 1
			end
		end
		local hinges = {}
		for n, c in pairs(hingeNames) do
			table.insert(hinges, n .. "x" .. c)
		end
		table.sort(hinges)
		print(("%s диагностика: %d частей, %d сварок, хинжи[%s], колёса[%s]"):format(
			TAG, parts, welds, table.concat(hinges, ", "), table.concat(wheelsInfo, " ")))
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
