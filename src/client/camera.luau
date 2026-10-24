-- Камера 2D: вид строго сбоку, следим за серединой между машинами.
-- Фон (небо, город, ближние силуэты) — настоящие 3D-детали за трассой
-- (строит сервер): параллакс получается сам за счёт расстояния до камеры.
-- Никаких GUI-слоёв поверх мира — мир всегда виден.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.config)

local state = ReplicatedStorage:WaitForChild(Config.Net.StateFolder)

local cam = workspace.CurrentCamera
local focusZ, focusY = -20, nil

RunService.RenderStepped:Connect(function()
	if not cam or cam.CameraType ~= Enum.CameraType.Scriptable then
		cam = workspace.CurrentCamera
		if not cam then return end
		cam.CameraType = Enum.CameraType.Scriptable
	end

	local scene = workspace:FindFirstChild("Scene")
	local race = scene and scene:FindFirstChild("Race")
	local phase = state:GetAttribute("Phase")

	-- камера ведёт ТОЛЬКО машину игрока (в гараже — вид на старт)
	local myCar = race and race:FindFirstChild("PlayerCar")
	if myCar and myCar.PrimaryPart then
		focusZ = myCar.PrimaryPart.Position.Z
		focusY = Config.Race.PlayerLaneTop + 5
	elseif focusY == nil then
		focusY = Config.Race.PlayerLaneTop + 6
	end

	local targetY = focusY + (phase == "Race" and 3 or 6)
	cam.FieldOfView = 55
	cam.CFrame = CFrame.lookAt(
		Vector3.new(100, targetY, focusZ),
		Vector3.new(0, focusY, focusZ)
	)
end)

return {}
