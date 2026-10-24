-- Drag 2D: клиент. Гараж-панель (деньги, RACE, результат), приборы машины
-- и дерево старта. Персонажа нет вообще — только экран и заезд.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.config)

local state = ReplicatedStorage:WaitForChild(Config.Net.StateFolder)
local remotes = ReplicatedStorage:WaitForChild(Config.Net.RemotesFolder)
local startRace = remotes:WaitForChild("StartRace")

local gui = Instance.new("ScreenGui")
gui.Name = "GarageUI"
gui.ResetOnSpawn = false
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Size = UDim2.new(0, 380, 0, 280)
panel.Position = UDim2.new(0, 16, 1, -16)
panel.AnchorPoint = Vector2.new(0, 1)
panel.BackgroundColor3 = Color3.fromRGB(10, 12, 18)
panel.BackgroundTransparency = 0.06
panel.BorderSizePixel = 0
panel.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = panel

local cash = Instance.new("TextLabel")
cash.Size = UDim2.new(1, -130, 0, 30)
cash.Position = UDim2.new(0, 12, 0, 8)
cash.BackgroundTransparency = 1
cash.Font = Enum.Font.GothamBold
cash.TextSize = 18
cash.TextColor3 = Color3.fromRGB(61, 224, 132)
cash.TextXAlignment = Enum.TextXAlignment.Left
cash.Text = "$0"
cash.Parent = panel

local ver = Instance.new("TextLabel")
ver.Size = UDim2.new(0, 120, 0, 16)
ver.Position = UDim2.new(1, -12, 0, 12)
ver.AnchorPoint = Vector2.new(1, 0)
ver.BackgroundTransparency = 1
ver.Font = Enum.Font.Code
ver.TextSize = 13
ver.TextColor3 = Color3.fromRGB(120, 130, 145)
ver.TextXAlignment = Enum.TextXAlignment.Right
ver.Text = "v" .. Config.Version
ver.Parent = panel

local result = Instance.new("TextLabel")
result.Size = UDim2.new(1, -24, 1, -140)
result.Position = UDim2.new(0, 12, 0, 44)
result.BackgroundTransparency = 1
result.Font = Enum.Font.Gotham
result.TextSize = 16
result.TextColor3 = Color3.fromRGB(210, 220, 232)
result.TextWrapped = true
result.TextXAlignment = Enum.TextXAlignment.Left
result.TextYAlignment = Enum.TextYAlignment.Top
result.Text = ""
result.Parent = panel

local raceBtn = Instance.new("TextButton")
raceBtn.Size = UDim2.new(1, -24, 0, 56)
raceBtn.Position = UDim2.new(0, 12, 1, -68)
raceBtn.BackgroundColor3 = Color3.fromRGB(16, 68, 44)
raceBtn.BorderSizePixel = 0
raceBtn.Font = Enum.Font.GothamBold
raceBtn.TextSize = 20
raceBtn.TextColor3 = Color3.fromRGB(230, 240, 235)
raceBtn.Text = "RACE  (1/4 мили)"
raceBtn.Parent = panel
local rc = Instance.new("UICorner")
rc.CornerRadius = UDim.new(0, 8)
rc.Parent = raceBtn
raceBtn.MouseButton1Click:Connect(function()
	startRace:FireServer()
end)

local function updateCash()
	cash.Text = "$" .. tostring(state:GetAttribute("Cash") or 0)
end
state:GetAttributeChangedSignal("Cash"):Connect(updateCash)
updateCash()

local function updateResult()
	result.Text = state:GetAttribute("ResultText") or ""
end
state:GetAttributeChangedSignal("ResultText"):Connect(updateResult)

-- ===== приборы + дерево старта =====
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

local raceFolder = workspace:WaitForChild("Scene"):WaitForChild("Race")
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
		dash.Text = ("%s  %d RPM  %d км/ч"):format(
			tostring(playerCar:GetAttribute("Gear") or 1),
			playerCar:GetAttribute("RPM") or 0,
			playerCar:GetAttribute("Kmh") or 0)
	else
		dash.Text = ""
	end
	tree.Text = state:GetAttribute("TreeText") or ""
end)

print("Drag 2D client boot, v" .. Config.Version)

require(script.camera)
require(script.car_control)
