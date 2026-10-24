-- CarService: ловит A-Chassis-машину, брошенную пользователем в Workspace,
-- держит её как шаблон и спавнит копии на старт. Оригинал не портится:
-- перенос живёт только внутри игровой сессии (после stop Play модель на месте).

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.config)

local CarService = {}

local TUNE_NAME = "A-Chassis Tune"
local TEMPLATE_NAME = "DefaultCar"

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

-- Перенести найденную модель в шаблоны (внутри сессии).
function CarService.absorb(model)
	if not isCarModel(model) then return end
	if state:GetAttribute("CarStatus") == "Ready" then
		warn("[CarService] машина уже захвачена, вторую игнорирую:", model.Name)
		return
	end

	local originalName = model.Name
	model.Name = TEMPLATE_NAME
	model.Parent = templates
	state:SetAttribute("CarStatus", "Ready")
	state:SetAttribute("CarName", originalName)
	print(("[CarService] машина захвачена: «%s» (Tune найден). Жми RACE — поставлю её на старт.")
		:format(originalName))
end

-- Спавн копии шаблона. cf — куда, tune — правки Tune до инициализации скриптов (v0.4: УОЗ и др.).
function CarService.spawn(cf, tune)
	local template = templates:FindFirstChild(TEMPLATE_NAME)
	if not template then
		state:SetAttribute("CarStatus", "Waiting")
		warn("[CarService] шаблона машины нет: закинь A-Chassis машину в Workspace (см. README)")
		return nil
	end

	CarService.despawn()

	local car = template:Clone()
	car.Name = "PlayerCar"
	car.Parent = raceFolder
	car:PivotTo(cf)
	currentCar = car
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

-- v0.2+: управление без персонажа. План: клиент стреляет в car.Drive.VirtualInput
-- (BindableEvent внутри Drive-скрипта, формат — фейковый InputObject: KeyCode W +
-- UserInputState.Begin). Для физики без водителя машину нужно отдать клиенту:
-- car:SetNetworkOwner(player) — иначе сервер владеет сборкой и клиентские
-- значения констрейнтов не применятся. ИИ-машину наоборот держит сервер
-- (SetNetworkOwner(nil)) и рулит констрейнтами напрямую.

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
		print("[CarService] жду машину: закинь A-Chassis модель в Workspace (см. README)")
	end
end

return CarService
