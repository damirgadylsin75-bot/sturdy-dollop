-- Камера 2D: вид строго сбоку, следим за серединой между машинами.
-- Параллакс: небо-градиент + дальняя и ближняя полосы движутся медленнее
-- трека — глаз видит глубину, как в Pixel Car Racer.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.config)

local player = Players.LocalPlayer
local state = ReplicatedStorage:WaitForChild(Config.Net.StateFolder)

local cam = workspace.CurrentCamera
local focusZ, focusY = 0, nil

-- ===== параллакс-фон =====
local bg = Instance.new("ScreenGui")
bg.Name = "ParallaxBG"
bg.IgnoreGuiInset = true
bg.DisplayOrder = -10
bg.Parent = player:WaitForChild("PlayerGui")

local sky = Instance.new("Frame")
sky.Size = UDim2.new(1, 0, 1, 0)
sky.BorderSizePixel = 0
sky.BackgroundColor3 = Config.color("Sky")
sky.Parent = bg
local skyGrad = Instance.new("UIGradient")
skyGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Config.color("Sky")),
	ColorSequenceKeypoint.new(1, Config.color("SkyLow")),
})
skyGrad.Rotation = 90
skyGrad.Parent = sky

-- полоса: ширина в два экрана, двигаем по модулю ширины экрана
local function band(color, heightFrac, yFrac, factor, transparency)
	local f = Instance.new("Frame")
	f.Size = UDim2.new(3, 0, heightFrac, 0)
	f.Position = UDim2.new(0, 0, yFrac, 0)
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency
	f.Parent = bg
	return { frame = f, factor = factor }
end

local bands = {
	band(Config.color("FarBand"), 0.22, 0.42, 0.06, 0.15),
	band(Config.color("NearBand"), 0.3, 0.56, 0.14, 0.2),
}

	local function updateBands()
		local vp = cam.ViewportSize
		for _, b in bands do
			-- машина едет вправо (-Z): фон должен уползать ВЛЕВО с параллаксом
			local offset = (-focusZ * b.factor) % vp.X
			b.frame.Position = UDim2.new(0, -offset, b.frame.Position.Y.Scale, 0)
		end
	end

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
		focusY = (Config.Race.PlayerLaneTop + Config.Race.PlayerLaneTop
			+ Config.Race.LaneGap) / 2 + 4
	elseif focusY == nil then
		focusY = Config.Race.PlayerLaneTop + 6
		focusZ = -20
	end

	local targetY = focusY + (phase == "Race" and 3 or 6)
	cam.FieldOfView = 55
	cam.CFrame = CFrame.lookAt(
		Vector3.new(120, targetY, focusZ),
		Vector3.new(0, focusY, focusZ)
	)

	updateBands()
end)

return {}
