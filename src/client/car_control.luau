-- DragDrive v0.6: физика и трансмиссия на сервере (шасси наше). Клиент
-- показывает приборы (из атрибутов машины), дерево старта/результат и шлёт
-- переключения ручной коробки. Сидя в машине газ/тормоз — родные W/S
-- VehicleSeat; встать нельзя (прыжок отключён сервером).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.config)

local player = Players.LocalPlayer

local state = ReplicatedStorage:WaitForChild(Config.Net.StateFolder)
local remotes = ReplicatedStorage:WaitForChild(Config.Net.RemotesFolder)
local carInput = remotes:WaitForChild("CarInput")

local raceFolder = workspace:WaitForChild("Scene"):WaitForChild("Race")

-- ===== HUD =====
local gui = Instance.new("ScreenGui")
gui.Name = "DriveHud"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local dash = Instance.new("TextLabel")
dash.Size = UDim2.new(0, 320, 0, 26)
dash.Position = UDim2.new(0, 12, 0, 10)
dash.BackgroundTransparency = 1
dash.Font = Enum.Font.Code
dash.TextSize = 18
dash.TextColor3 = Color3.fromRGB(235, 240, 245)
dash.TextXAlignment = Enum.TextXAlignment.Left
dash.Text = ""
dash.Parent = gui

local tree = Instance.new("TextLabel")
tree.Size = UDim2.new(1, 0, 0, 42)
tree.AnchorPoint = Vector2.new(0.5, 0)
tree.Position = UDim2.new(0.5, 0, 0, 52)
tree.BackgroundTransparency = 1
tree.Font = Enum.Font.GothamBold
tree.TextSize = 26
tree.TextColor3 = Color3.fromRGB(255, 210, 80)
tree.Text = ""
tree.Parent = gui

-- клавиши ручной коробки
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	local k = input.KeyCode
	if k == Enum.KeyCode.M then
		carInput:FireServer("mode")
	elseif k == Enum.KeyCode.LeftShift then
		carInput:FireServer("up")
	elseif k == Enum.KeyCode.LeftControl then
		carInput:FireServer("down")
	end
end)

-- приборы: из атрибутов своей машины
local playerCar
local function scan()
	playerCar = raceFolder:FindFirstChild("PlayerCar")
end
raceFolder.ChildAdded:Connect(function()
	task.defer(scan)
end)
raceFolder.ChildRemoved:Connect(function()
	task.defer(scan)
end)
scan()

RunService.Heartbeat:Connect(function()
	if playerCar and playerCar.Parent then
		local gear = playerCar:GetAttribute("Gear")
		local rpm = playerCar:GetAttribute("RPM") or 0
		local kmh = playerCar:GetAttribute("Kmh") or 0
		dash.Text = ("%s  %d RPM  %d км/ч"):format(
			tostring(gear or 1), rpm, kmh)
	else
		dash.Text = ""
	end
	tree.Text = state:GetAttribute("TreeText") or ""
end)
