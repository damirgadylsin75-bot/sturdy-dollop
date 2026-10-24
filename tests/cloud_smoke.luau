-- Cloud smoke: версия + сборка НАШЕГО шасси на настоящем сервере Roblox.
-- Строим машину, ждём секунду, проверяем: 4 мотор-хинжа, сиденье на месте,
-- рама не провалилась сквозь мир. Отчёт идёт в PR-комментарий.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local okConfig, Config = pcall(function()
	return require(ReplicatedStorage.Shared.config)
end)
if not okConfig then
	return { ok = false, err = "config: " .. tostring(Config) }
end

local result = { version = Config.Version }

local gs = ReplicatedStorage:FindFirstChild(Config.Net.StateFolder)
result.gameState = gs and gs:GetAttribute("Phase") or "no-state"

local okCar, CarService = pcall(function()
	return require(ServerScriptService.Game.car_service)
end)
if not okCar then
	return { ok = false, version = Config.Version, err = "car_service: " .. tostring(CarService) }
end

local car, st
local okBuild, buildErr = pcall(function()
	car, st = CarService.buildCar("SmokeCar", CFrame.new(0, 3, 0), true)
end)
if not okBuild or not car then
	return { ok = false, version = Config.Version, err = "build: " .. tostring(buildErr) }
end

task.wait(1.2)

local hinges = 0
local seat = car:FindFirstChild("DriverSeat", true)
local bodyParts = 0
for _, d in car:GetDescendants() do
	if d:IsA("HingeConstraint") then hinges = hinges + 1 end
	if d:IsA("BasePart") then bodyParts = bodyParts + 1 end
end
local base = car:FindFirstChild("Frame")
local baseY = base and math.floor(base.Position.Y * 10) / 10 or -999
local fellAsleep = base and base.Anchored or false

result.hinges = hinges
result.seat = seat ~= nil
result.parts = bodyParts
result.baseY = baseY
result.ok = (hinges == 4) and (seat ~= nil) and (not fellAsleep)
return result
