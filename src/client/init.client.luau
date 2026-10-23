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
local Hud = require(script.hud)

CameraRig.init()
Fx.init()
Input.init(cityData)
Hud.init(cityData)

-- a restarted round generates a new city: re-seed client-side map data
state:GetAttributeChangedSignal("Seed"):Connect(function()
	local newSeed = state:GetAttribute("Seed")
	if newSeed then
		Input.setCity(MapGen.generate(newSeed))
	end
end)
