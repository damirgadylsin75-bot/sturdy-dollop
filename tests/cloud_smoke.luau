-- Cloud smoke: версия + сборка 2D-машины на настоящем сервере Roblox.
-- Строим машину над собственным ground-куском, ждём, проверяем: 2 хинжа,
-- машина стоит на колёсах (не провалилась), 2D-фиксации работают.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local okConfig, Config = pcall(function()
	return require(ReplicatedStorage.Shared.config)
end)
if not okConfig then
	return { ok = false, err = "config: " .. tostring(Config) }
end

local result = { version = Config.Version }

local okCar, CarService = pcall(function()
	return require(ServerScriptService.Game.car_service)
end)
if not okCar then
	return { ok = false, version = Config.Version, err = "car_service: " .. tostring(CarService) }
end

-- свой мирок: пол на Y=0
local ground = Instance.new("Part")
ground.Anchored = true
ground.Size = Vector3.new(80, 2, 400)
ground.Position = Vector3.new(0, -1, 0)
ground.Parent = workspace

local car, st
local okBuild, buildErr = pcall(function()
	car, st = CarService.buildCar("SmokeCar", CFrame.new(0, 3.85, 0), true, 0, workspace)
end)
if not okBuild or not car then
	return { ok = false, version = Config.Version, err = "build: " .. tostring(buildErr) }
end

task.wait(1.2)

local hinges, textures = 0, 0
for _, d in car:GetDescendants() do
	if d:IsA("HingeConstraint") then hinges = hinges + 1 end
	if d:IsA("Texture") then textures = textures + 1 end
end
local base = car:FindFirstChild("Body")
local baseY = base and math.floor(base.Position.Y * 100) / 100 or -999
local vx = base and math.abs(base.AssemblyLinearVelocity.X) or 999

result.hinges = hinges
result.textures = textures
result.baseY = baseY
result.driftX = math.floor(vx * 100) / 100
-- машина должна стоять на колёсах: база около 3.6-3.8 (упала бы — ниже/улетела)
result.ok = (hinges == 2) and (textures == 4) and baseY > 2.5 and baseY < 4.5 and vx < 1
return result
