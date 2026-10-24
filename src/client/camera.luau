-- Камера: в гараже — вид на стартовую линию сбоку и чуть сверху,
-- в заезде — следим за серединой между машинами, обе в кадре.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.config)

local CameraRig = {}

local cam = workspace.CurrentCamera

local GARAGE_CAM = CFrame.lookAt(
	Vector3.new(74, 30, 10),
	Vector3.new(0, 4, -46)
)
local RACE_SIDE = Vector3.new(66, 24, 0) -- сбоку и сверху от точки фокуса

local state

local function raceFocus()
	local scene = workspace:FindFirstChild("Scene")
	local race = scene and scene:FindFirstChild("Race")
	if not race then return nil end

	local sum = Vector3.zero
	local n = 0
	for _, m in race:GetChildren() do
		if m:IsA("Model") then
			local ok, pivot = pcall(m.GetPivot, m)
			if ok then
				sum = sum + pivot.Position
				n = n + 1
			end
		end
	end
	if n == 0 then return nil end
	return sum / n
end

RunService.RenderStepped:Connect(function()
	if not cam or cam.CameraType ~= Enum.CameraType.Scriptable then
		cam = workspace.CurrentCamera
		if not cam then return end
		cam.CameraType = Enum.CameraType.Scriptable
	end

	local phase = state and state:GetAttribute("Phase")
	if phase == "Race" then
		local focus = raceFocus()
		if focus then
			cam.FieldOfView = 62
			cam.CFrame = CFrame.lookAt(focus + RACE_SIDE, focus)
			return
		end
	end

	cam.FieldOfView = 60
	cam.CFrame = GARAGE_CAM
end)

function CameraRig.start(stateRef)
	state = stateRef
end

return CameraRig
