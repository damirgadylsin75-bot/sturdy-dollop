-- CarBridge: машина управляет собой РОДНОЙ системой A-Chassis (её скрипты
-- не глушатся и не удаляются — модель живёт своей жизнью). Наша роль рядом:
-- 1) сервер отдаёт физику игроку (CarService.setOwner) — иначе родные команды
--    на констрейнты не подействуют;
-- 2) включаем зажигание, если сборка не завелась сама (без водителя);
-- 3) HUD из родных Values модели (RPM/Gear/Velocity), никакого своего
--    «крутилкина»: педали и передачи — родные бинды A-Chassis
--    (настраиваются в Settings внутри модели).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.config)

local player = Players.LocalPlayer

local Bridge = {}

local car, values, hud
local hudClock = 0

local function makeHud()
	local gui = Instance.new("ScreenGui")
	gui.Name = "DriveHud"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")
	hud = Instance.new("TextLabel")
	hud.Size = UDim2.new(0, 320, 0, 26)
	hud.Position = UDim2.new(0, 12, 0, 10)
	hud.BackgroundTransparency = 1
	hud.Font = Enum.Font.Code
	hud.TextSize = 18
	hud.TextColor3 = Color3.fromRGB(235, 240, 245)
	hud.TextXAlignment = Enum.TextXAlignment.Left
	hud.Text = ""
	hud.Parent = gui
end

local function attach(carModel)
	-- даём родной системе собрать/завести машину
	task.wait(1)
	if not carModel.Parent then return end
	car = carModel
	values = carModel:FindFirstChild("Values")

	local isOn = carModel:FindFirstChild("IsOn")
	if isOn and isOn:IsA("BoolValue") and not isOn.Value then
		isOn.Value = true -- без сидящего водителя некоторые сборки не стартуют
	end

	makeHud()
	print("[CarBridge] мост готов: управление — родные бинды модели (A-Chassis)")
end

RunService.Heartbeat:Connect(function(dt)
	if not car or not car.Parent then
		if hud then hud.Text = "" end
		return
	end

	hudClock = hudClock + dt
	if hudClock < 0.1 then return end
	hudClock = 0

	local function num(name)
		local v = values and values:FindFirstChild(name)
		if v and (v:IsA("NumberValue") or v:IsA("IntValue")) then return v.Value end
		return nil
	end

	local rpm = num("RPM") or 0
	local gear = num("Gear") or 0
	local speed = math.abs(num("Velocity") or 0)
	local kmh = speed * 3.6 / Config.Race.StudsPerMeter
	local gearText = gear < 0 and "R" or tostring(gear)
	hud.Text = ("%s  %d RPM  %d км/ч"):format(gearText, rpm, kmh)
end)

-- следим за появлением нашей машины
local raceFolder = workspace:WaitForChild("Scene"):WaitForChild("Race")
raceFolder.ChildAdded:Connect(function(child)
	if child.Name == "PlayerCar" and child:IsA("Model") then
		task.spawn(attach, child)
	end
end)

function Bridge.start() end

return Bridge
