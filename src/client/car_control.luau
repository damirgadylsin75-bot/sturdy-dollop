-- Клиентский ввод: W/стрелка вверх — газ, S/вниз — тормоз,
-- M — авто/ручная, Shift/Ctrl — передачи (в ручной).
-- Педали летят на сервер, вся физика там.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.config)

local player = Players.LocalPlayer

local state = ReplicatedStorage:WaitForChild(Config.Net.StateFolder)
local remotes = ReplicatedStorage:WaitForChild(Config.Net.RemotesFolder)
local pedal = remotes:WaitForChild("Pedal")
local gear = remotes:WaitForChild("Gear")

local gas, brake = false, false

local function sendPedal()
	pedal:FireServer(gas, brake)
end

local function keyIsPedal(k)
	return k == Enum.KeyCode.W or k == Enum.KeyCode.Up
		or k == Enum.KeyCode.S or k == Enum.KeyCode.Down
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	local k = input.KeyCode
	if k == Enum.KeyCode.W or k == Enum.KeyCode.Up then
		gas = true
		sendPedal()
	elseif k == Enum.KeyCode.S or k == Enum.KeyCode.Down then
		brake = true
		sendPedal()
	elseif k == Enum.KeyCode.M then
		gear:FireServer("mode")
	elseif k == Enum.KeyCode.LeftShift then
		gear:FireServer("up")
	elseif k == Enum.KeyCode.LeftControl then
		gear:FireServer("down")
	end
end)

UserInputService.InputEnded:Connect(function(input)
	local k = input.KeyCode
	if k == Enum.KeyCode.W or k == Enum.KeyCode.Up then
		gas = false
		sendPedal()
	elseif k == Enum.KeyCode.S or k == Enum.KeyCode.Down then
		brake = false
		sendPedal()
	end
end)

-- если фокус в чате — педали в ноль, чтобы машина не ехала сама
UserInputService.TextBoxFocused:Connect(function()
	if gas or brake then
		gas, brake = false, false
		sendPedal()
	end
end)

return {}
