-- Client entry: regenerates the same city from the shared seed (deterministic
-- mapgen means zero map replication), then boots camera, input, fx and hud.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("config"))
local MapGen = require(ReplicatedStorage.Shared.mapgen)

local state = ReplicatedStorage:WaitForChild(Config.Net.StateFolder)

local seed = state:GetAttribute("Seed")
while not seed do
	state:GetAttributeChangedSignal("Seed"):Wait()
	seed = state:GetAttribute("Seed")
end

local cityData = MapGen.generate(seed)

local CameraRig = require(script.camera)
local Input = require(script.input)
local Fx = require(script.fx)
local Crt = require(script.crt)
local Hud = require(script.hud)

-- Self-diagnostics: if a client module fails to boot, show the reason ON
-- SCREEN (instead of a mysterious half-broken state that needs the console).
local function guard(name, fn)
	local ok, err = pcall(fn)
	if not ok then
		warn("client boot error [" .. name .. "]: " .. tostring(err))
		local Players = game:GetService("Players")
		local gui = Instance.new("ScreenGui")
		gui.IgnoreGuiInset = true
		gui.ResetOnSpawn = false
		gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		local frame = Instance.new("Frame")
		frame.Size = UDim2.new(1, 0, 0, 110)
		frame.Position = UDim2.new(0, 0, 0, 0)
		frame.BackgroundColor3 = Color3.fromRGB(60, 12, 12)
		frame.BorderSizePixel = 0
		frame.Parent = gui
		local text = Instance.new("TextLabel")
		text.Size = UDim2.new(1, -20, 1, -12)
		text.Position = UDim2.new(0, 10, 0, 6)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.Code
		text.TextSize = 15
		text.TextColor3 = Color3.fromRGB(255, 120, 120)
		text.TextWrapped = true
		text.TextXAlignment = Enum.TextXAlignment.Left
		text.Text = "CLIENT ERROR [" .. name .. "] v" .. (Config.Version or "?") .. ": " .. tostring(err)
		text.Parent = frame
	end
	return ok
end

guard("camera", CameraRig.init)
guard("fx", Fx.init)
guard("crt", Crt.init)
guard("input", function()
	Input.init(cityData)
end)
guard("hud", function()
	Hud.init(cityData)
end)

-- late diagnostics: if the city failed to reach THIS client, say so on screen.
-- Classic cause: StreamingEnabled left on in a stale place (nothing streams
-- to a client without a character).
task.delay(5, function()
	local root = workspace:FindFirstChild("CityRoot")
	local parts = 0
	if root then
		parts = #root:GetDescendants()
	end
	if parts < 10 then
		local Players = game:GetService("Players")
		local gui = Instance.new("ScreenGui")
		gui.IgnoreGuiInset = true
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 50
		gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		local banner = Instance.new("TextLabel")
		banner.Size = UDim2.new(1, -40, 0, 64)
		banner.Position = UDim2.new(0.5, 0, 0, 12)
		banner.AnchorPoint = Vector2.new(0.5, 0)
		banner.BackgroundColor3 = Color3.fromRGB(96, 62, 10)
		banner.BorderSizePixel = 0
		banner.Font = Enum.Font.Code
		banner.TextSize = 14
		banner.TextColor3 = Color3.fromRGB(255, 210, 120)
		banner.TextWrapped = true
		banner.Text = ("ДИАГНОСТИКА v%s: город не прогрузился на клиенте (%d частей). "
			.. "Если у Workspace включён StreamingEnabled — выключи его в свойствах Workspace и пересинк. "
			.. "Наши плейс-настройки делают это автоматически."):format(Config.Version or "?", parts)
		banner.Parent = gui
	end
end)

-- a restarted round generates a new city: re-seed client-side map data
state:GetAttributeChangedSignal("Seed"):Connect(function()
	local newSeed = state:GetAttribute("Seed")
	if newSeed then
		Input.setCity(MapGen.generate(newSeed))
	end
end)
