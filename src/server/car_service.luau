-- CarService: ловит A-Chassis-машину, брошенную пользователем в Workspace,
-- держит её как шаблон и спавнит копии на старт. Управляет машиной наш
-- DragDrive (src/client/car_control.luau), поэтому из чужих скриптов
-- выживает ТОЛЬКО модуль Tune — весь остальной «начинок» моделей с Toolbox
-- (чат-мусор, чужие админки, «EpicLights», битые приватные звуки) сносится.

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

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

-- Вычистить всё, кроме модуля Tune и его внутренностей (Units/CustomEngine):
-- наш DragDrive сам рулит хинжами, а посторонние скрипты моделей — источник
-- ошибок и бэкдоров. Звуки тоже сносим: в чужих моделях аудио обычно
-- приватное («User is not authorized») и только спамит лог.
local function sanitize(model)
	local removed, names, seen = 0, {}, {}
	local tuneModule = model:FindFirstChild(TUNE_NAME, true)

	for _, d in model:GetDescendants() do
		local doomed = false
		if d:IsA("Sound") then
			doomed = true
		elseif d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript") then
			doomed = not (tuneModule and (d == tuneModule or d:IsDescendantOf(tuneModule)))
		end
		if doomed then
			d:Destroy()
			removed = removed + 1
			if not seen[d.Name] then
				seen[d.Name] = true
				table.insert(names, d.Name)
			end
		end
	end
	return removed, names
end

-- Перенести найденную модель в шаблоны (внутри сессии).
function CarService.absorb(model)
	if not isCarModel(model) then return end
	if state:GetAttribute("CarStatus") == "Ready" then
		warn("[CarService] машина уже захвачена, вторую игнорирую:", model.Name)
		return
	end

	local total, junkNames = sanitize(model)
	if total > 0 then
		local show = table.concat(junkNames, ", ")
		if #junkNames > 8 then
			show = table.concat(junkNames, ", ", 1, 8) .. ", …"
		end
		print(("[CarService] чистка модели: удалено %d посторонних скриптов/звуков: %s")
			:format(total, show))
	end

	local originalName = model.Name
	model.Name = TEMPLATE_NAME
	model.Parent = templates
	state:SetAttribute("CarStatus", "Ready")
	state:SetAttribute("CarName", originalName)
	print(("[CarService] машина захвачена: «%s» (Tune найден). Жми RACE — поставлю её на старт.")
		:format(originalName))
end

-- Отдать физику машины игроку: без этого клиентские команды на хинжи
-- не подействуют. Вызывается с небольшой задержкой после спавна.
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

-- Спавн копии шаблона. tune — правки Tune до инициализации (v0.4: УОЗ и др.).
function CarService.spawn(cf, ownerPlayer)
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

	-- модели с Toolbox иногда лежат с заякоренными частями — машине нужно уметь падать на подвеску
	for _, p in car:GetDescendants() do
		if p:IsA("BasePart") and p.Anchored then
			p.Anchored = false
		end
	end

	car:SetAttribute("OwnerUserId", ownerPlayer and ownerPlayer.UserId or 0)
	currentCar = car

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
		print("[CarService] жду машину: закинь A-Chassis модель в Workspace (см. README)")
	end
end

return CarService
