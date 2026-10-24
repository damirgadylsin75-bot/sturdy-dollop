-- CarService: ловит A-Chassis-машину, брошенную пользователем в Workspace,
-- держит её как шаблон и спавнит копии на старт. Управляет машиной наш
-- DragDrive (src/client/car_control.luau), поэтому чужие скрипты машине не
-- нужны ВООБЩЕ — они источник ошибок (DeleteOnChat, Handler, EpicLights) и
-- бэкдоров. Чистим жёстко: Workspace целиком + каждую заспавненную копию.

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

-- Вычистить в контейнере всё, кроме Tune-модулей и их внутренностей.
-- Порядок важен: сначала ВСЁ лишнее отключаем (Disabled = true, чтобы ни один
-- скрипт не запустился посреди чистки), потом удаляем. Звуки сносим всегда —
-- у чужих моделей аудио приватное («User is not authorized») и лишь спамит лог.
local function purge(container)
	assert(container, "purge: нет контейнера")

	-- все Tune-модули в этом контейнере — их и их детей не трогаем
	local tunes = {}
	for _, d in container:GetDescendants() do
		if d:IsA("ModuleScript") and d.Name == TUNE_NAME then
			table.insert(tunes, d)
		end
	end

	local function protected(d)
		for _, t in tunes do
			if d == t or d:IsDescendantOf(t) then return true end
		end
		return false
	end

	local doomed = {}
	for _, d in container:GetDescendants() do
		if d:IsA("Sound") then
			table.insert(doomed, d)
		elseif (d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript"))
			and not protected(d) then
			pcall(function()
				d.Disabled = true
			end)
			table.insert(doomed, d)
		end
	end

	local removed, names, seen = 0, {}, {}
	for _, d in doomed do
		if d.Parent then
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

local function logRemoved(total, names, what)
	if total == 0 then return end
	local show = table.concat(names, ", ")
	if #names > 8 then
		show = table.concat(names, ", ", 1, 8) .. ", …"
	end
	print(("%s чистка (%s): удалено %d: %s"):format(TAG, what, total, show))
end

-- Перенести найденную модель в шаблоны (внутри сессии).
function CarService.absorb(model)
	if not isCarModel(model) then return end
	if state:GetAttribute("CarStatus") == "Ready" then
		-- вторая машина: декорацией, без скриптов, чтобы ничего не выполнялось
		local total, names = purge(model)
		logRemoved(total, names, "вторая машина")
		warn(("%s машина уже захвачена — вторая («%s») стоит декорацией без скриптов")
			:format(TAG, model.Name))
		return
	end

	local total, names = purge(model)
	logRemoved(total, names, "захват")

	local originalName = model.Name
	model.Name = TEMPLATE_NAME
	model.Parent = templates
	state:SetAttribute("CarStatus", "Ready")
	state:SetAttribute("CarName", originalName)
	print(("%s машина захвачена: «%s» (Tune найден). Жми RACE — поставлю её на старт.")
		:format(TAG, originalName))
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
		warn(("%s шаблона машины нет: закинь A-Chassis машину в Workspace (см. README)"):format(TAG))
		return nil
	end

	CarService.despawn()

	local car = template:Clone()

	-- страховка: даже если что-то попало в шаблон после чистки — снесём ДО появления в мире
	local total, names = purge(car)
	logRemoved(total, names, "спавн")

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

	-- анти-инъекция: чужие «раздающие» скрипты могут подложить своё в новую
	-- модель через секунду после спавна — повторяем чистку
	task.delay(1, function()
		if car.Parent then
			local t2, n2 = purge(car)
			logRemoved(t2, n2, "спавн+1с")
		end
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

-- Чистка всего Workspace: наша игра живёт только в Scene, любой скрипт или
-- звук вне Tune-модулей машин — мусор из Toolbox и выполняться не должен.
function CarService.purgeWorkspace()
	local total, names = purge(workspace)
	logRemoved(total, names, "Workspace")
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

	-- что бы ни появлялось в мире — скрипты/звуки вне Tune не живут
	workspace.DescendantAdded:Connect(function(d)
		if not (d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript") or d:IsA("Sound")) then
			return
		end
		task.defer(function()
			if not d.Parent then return end
			local node = d
			while node and node ~= workspace do
				if node:IsA("ModuleScript") and node.Name == TUNE_NAME then
					return -- внутренности Tune (Units, CustomEngine) — легитимные
				end
				node = node.Parent
			end
			if d:IsA("Sound") then
				d:Destroy()
				return
			end
			if d:IsA("ModuleScript") then
				return -- прочие модули пусть лежат (не выполняются сами)
			end
			pcall(function()
				d.Disabled = true
			end)
			d:Destroy()
			print(("%s перехвачен и удалён чужой скрипт: %s"):format(TAG, d.Name))
		end)
	end)

	-- и общий проход по уже существующему (на случай, если что-то живо с прошлого раза)
	CarService.purgeWorkspace()

	if state:GetAttribute("CarStatus") ~= "Ready" then
		state:SetAttribute("CarStatus", "Waiting")
		print(("%s жду машину: закинь A-Chassis модель в Workspace (см. README)"):format(TAG))
	end
end

return CarService
