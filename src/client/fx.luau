-- Transient visual effects driven by server events.
-- The server only sends "what happened"; all particles/lights are local.

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("config"))

local Fx = {}

local folder

local function newPart(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		p[k] = v
	end
	p.Parent = folder
	return p
end

local function flatDisc(x, z, thickness, diameter, color, transparency)
	return newPart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(thickness, diameter, diameter),
		CFrame = CFrame.new(x, 0.9, z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Transparency = transparency or 0.15,
	})
end

local POOF_COLORS = {
	zombie = Color3.fromRGB(61, 224, 112),
	civilian = Color3.fromRGB(233, 245, 210),
	convert = Color3.fromRGB(24, 92, 48),
	bar = Color3.fromRGB(232, 143, 26),
}

local function poof(payload)
	local color = POOF_COLORS[payload.tone] or Color3.fromRGB(255, 255, 255)
	local ball = newPart({
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2, 2, 2),
		CFrame = CFrame.new(payload.x, 1.6, payload.y or payload.z),
		Color = color,
		Transparency = 0.1,
	})
	local target = payload.tone == "convert" and 4 or 6
	TweenService:Create(ball, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(target, target, target),
		Transparency = 1,
	}):Play()
	task.delay(0.35, function() ball:Destroy() end)
end

local function explosion(payload)
	local r = payload.r or 20
	local x, y, z = payload.x, payload.y or 1.5, payload.z
	local ball = newPart({
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(3, 3, 3),
		CFrame = CFrame.new(x, y, z),
		Color = Color3.fromRGB(255, 176, 64),
		Transparency = 0.05,
	})
	TweenService:Create(ball, TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(r * 2, r * 2, r * 2),
		Transparency = 1,
	}):Play()
	task.delay(0.5, function() ball:Destroy() end)

	local ring = flatDisc(x, z, 0.7, 5, Color3.fromRGB(255, 200, 90), 0.1)
	TweenService:Create(ring, TweenInfo.new(0.5), {
		Size = Vector3.new(0.2, r * 2.2, r * 2.2),
		Transparency = 1,
	}):Play()
	task.delay(0.6, function() ring:Destroy() end)
end

local function bomber(payload)
	local from = Vector3.new(payload.from.x, 130, payload.from.z)
	local to = Vector3.new(payload.to.x, 130, payload.to.z)
	local plane = newPart({
		Size = Vector3.new(15, 2.5, 32),
		Color = Color3.fromRGB(58, 64, 78),
		Material = Enum.Material.Metal,
		CFrame = CFrame.lookAt(from, to),
	})
	task.delay(payload.delay or 0, function()
		if not plane.Parent then return end
		local dur = payload.duration or 4
		TweenService:Create(plane, TweenInfo.new(dur, Enum.EasingStyle.Linear), {
			CFrame = CFrame.lookAt(to, to + (to - from)),
		}):Play()
		task.delay(dur, function() plane:Destroy() end)
	end)
end

local function missile(payload)
	local to = Vector3.new(payload.to.x, 1.2, payload.to.z)
	local from = Vector3.new(payload.from.x, payload.from.y or 80, payload.from.z or (to.Z + 340))
	local delay = payload.delay or 1.1
	local m = newPart({
		Size = Vector3.new(1, 1, 8),
		Color = Color3.fromRGB(235, 240, 250),
		CFrame = CFrame.lookAt(from, to),
	})
	TweenService:Create(m, TweenInfo.new(delay, Enum.EasingStyle.Linear), {
		CFrame = CFrame.lookAt(to, to + (to - from)),
	}):Play()
	task.delay(delay + 0.1, function() m:Destroy() end)
end

local function tracer(payload)
	local a = Vector3.new(payload.from.x, payload.from.y, payload.from.z)
	local b = Vector3.new(payload.to.x, payload.to.y, payload.to.z)
	local len = (b - a).Magnitude
	if len < 1 then return end
	local beam = newPart({
		Size = Vector3.new(0.25, 0.25, len),
		CFrame = CFrame.lookAt((a + b) / 2, b),
		Color = Config.color("Sniper"),
		Transparency = 0.05,
	})
	TweenService:Create(beam, TweenInfo.new(0.16), { Transparency = 1 }):Play()
	task.delay(0.2, function() beam:Destroy() end)
end

local function savedPing(payload)
	local disc = flatDisc(payload.x, payload.z, 0.5, 4, Config.color("Evac"), 0.1)
	TweenService:Create(disc, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.1, 14, 14),
		Transparency = 1,
	}):Play()
	task.delay(0.55, function() disc:Destroy() end)
end

function Fx.init()
	folder = Instance.new("Folder")
	folder.Name = "ClientFx"
	folder.Parent = workspace

	local remotesFolder = ReplicatedStorage:WaitForChild(Config.Net.RemotesFolder)
	local eventEvent = remotesFolder:WaitForChild(Config.Net.Event)

	eventEvent.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then return end
		local kind = payload.kind
		if kind == "explosion" then
			explosion(payload)
		elseif kind == "bomber" then
			bomber(payload)
		elseif kind == "missile" then
			missile(payload)
		elseif kind == "tracer" then
			tracer(payload)
		elseif kind == "savedPing" then
			savedPing(payload)
		elseif kind == "poof" then
			poof(payload)
		elseif kind == "barBreak" then
			poof({ x = payload.x, z = payload.z, tone = "bar" })
		end
	end)
end

return Fx
