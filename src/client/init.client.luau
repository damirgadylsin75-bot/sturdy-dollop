-- Drag II: клиент. Гараж-экран (v0.1 — каркас UI).

local Players = game:GetService("Players")
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
panel.Size = UDim2.new(0, 380, 0, 260)
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
cash.Size = UDim2.new(1, -24, 0, 30)
cash.Position = UDim2.new(0, 12, 0, 8)
cash.BackgroundTransparency = 1
cash.Font = Enum.Font.GothamBold
cash.TextSize = 18
cash.TextColor3 = Color3.fromRGB(61, 224, 132)
cash.TextXAlignment = Enum.TextXAlignment.Left
cash.Text = "$0"
cash.Parent = panel

local function updateCash()
	cash.Text = "$" .. tostring(state:GetAttribute("Cash") or 0)
end
state:GetAttributeChangedSignal("Cash"):Connect(updateCash)
updateCash()

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

print("Drag II client boot, v" .. Config.Version)

require(script.camera).start(state)
