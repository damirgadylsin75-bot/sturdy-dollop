-- CRT overlay: scanlines, phosphor tint, vignette, flicker and a slow
-- rolling bar on top of everything. Pure engine UI (no external assets).
-- Toggle with C. Flattened via CanvasGroup so scanlines stay cheap.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("config"))

local Crt = {}

local gui

function Crt.setEnabled(on)
	if gui then
		gui.Enabled = on
	end
end

function Crt.toggle()
	if gui then
		gui.Enabled = not gui.Enabled
	end
end

function Crt.init()
	gui = Instance.new("ScreenGui")
	gui.Name = "CrtOverlay"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 100
	gui.Enabled = Config.Interface.CRTEnabled ~= false

	-- phosphor tint (slight green cast, like an old tube)
	local tint = Instance.new("Frame")
	tint.Size = UDim2.new(1, 0, 1, 0)
	tint.BackgroundColor3 = Color3.fromRGB(168, 255, 190)
	tint.BackgroundTransparency = 0.968
	tint.BorderSizePixel = 0
	tint.Parent = gui

	-- scanlines: one flattened CanvasGroup with 240 thin lines
	pcall(function()
		local cg = Instance.new("CanvasGroup")
		cg.Size = UDim2.new(1, 0, 1, 0)
		cg.BackgroundTransparency = 1
		cg.GroupTransparency = 0.5
		cg.BorderSizePixel = 0
		cg.Parent = gui
		for i = 0, 239 do
			local line = Instance.new("Frame")
			line.Size = UDim2.new(1, 0, 0, 1)
			line.Position = UDim2.new(0, 0, i / 240, 0)
			line.BackgroundColor3 = Color3.new(0, 0, 0)
			line.BackgroundTransparency = 0.35
			line.BorderSizePixel = 0
			line.Parent = cg
		end
	end)

	-- vignette: four gradient edges
	local function vignette(side)
		local f = Instance.new("Frame")
		f.BackgroundColor3 = Color3.new(0, 0, 0)
		f.BorderSizePixel = 0
		local g = Instance.new("UIGradient")
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.12),
			NumberSequenceKeypoint.new(1, 1),
		})
		if side == "top" then
			f.Size = UDim2.new(1, 0, 0.12, 0)
			g.Rotation = 90
		elseif side == "bottom" then
			f.Size = UDim2.new(1, 0, 0.12, 0)
			f.Position = UDim2.new(0, 0, 0.88, 0)
			g.Rotation = -90
		elseif side == "left" then
			f.Size = UDim2.new(0.1, 0, 1, 0)
			g.Rotation = 0
		else
			f.Size = UDim2.new(0.1, 0, 1, 0)
			f.Position = UDim2.new(0.9, 0, 0, 0)
			g.Rotation = 180
		end
		g.Parent = f
		f.Parent = gui
	end
	vignette("top")
	vignette("bottom")
	vignette("left")
	vignette("right")

	-- subtle brightness flicker
	local flicker = Instance.new("Frame")
	flicker.Size = UDim2.new(1, 0, 1, 0)
	flicker.BackgroundColor3 = Color3.new(0, 0, 0)
	flicker.BackgroundTransparency = 0.978
	flicker.BorderSizePixel = 0
	flicker.Parent = gui
	TweenService:Create(
		flicker,
		TweenInfo.new(0.18, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ BackgroundTransparency = 0.992 }
	):Play()

	-- slow rolling bar
	local roll = Instance.new("Frame")
	roll.Size = UDim2.new(1, 0, 0.07, 0)
	roll.Position = UDim2.new(0, 0, -0.07, 0)
	roll.BackgroundColor3 = Color3.fromRGB(225, 255, 235)
	roll.BackgroundTransparency = 0.9
	roll.BorderSizePixel = 0
	roll.Parent = gui
	local rg = Instance.new("UIGradient")
	rg.Rotation = 90
	rg.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	rg.Parent = roll
	local rollTween = TweenService:Create(
		roll,
		TweenInfo.new(9, Enum.EasingStyle.Linear),
		{ Position = UDim2.new(0, 0, 1.07, 0) }
	)
	rollTween:Play()
	rollTween.Completed:Connect(function()
		roll.Position = UDim2.new(0, 0, -0.07, 0)
		rollTween:Play()
	end)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.C then
			Crt.toggle()
		end
	end)
end

return Crt
