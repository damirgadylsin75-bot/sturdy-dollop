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

	local zSum, n = 0, 0
	if race then
		for _, m in race:GetChildren() do
			if m:IsA("Model") and m.PrimaryPart then
				zSum = zSum + m.PrimaryPart.Position.Z
				n = n + 1
			end
		end
	end

	if n > 0 then
		focusZ = zSum / n
		focusY = (Config.Race.PlayerLaneTop * 2 + Config.Race.LaneGap) / 2 + 4
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
