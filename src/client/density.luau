-- Proximity whitening (pure client, zero replication cost):
-- the more entities crowd within DensityGlow.Radius of a dot, the closer
-- its color lerps toward white (capped, gradual). Runs on a spatial hash
-- every DensityGlow.Interval seconds; snapshot of each dot's base color
-- is kept in a weak table so spawn/despawn is free.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("config"))

local Density = {}

local WHITE = Color3.new(1, 1, 1)

function Density.init()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	-- wait for the server-built city (it appears right after replication)
	task.spawn(function()
		local pop = nil
		while not pop do
			local root = workspace:FindFirstChild("CityRoot")
			if root then
				pop = root:FindFirstChild("Population")
			end
			if not pop then
				task.wait(0.5)
			end
		end

		local cfg = Config.Interface.DensityGlow
		local baseColors = setmetatable({}, { __mode = "k" })
		local radius = cfg.Radius
		local rSq = radius * radius
		local cell = radius -- bucket size ~ radius keeps 3x3 cells sufficient
		local acc = 0

		RunService.Heartbeat:Connect(function(dt)
			acc = acc + dt
			if acc < cfg.Interval then return end
			acc = 0

			local zoms = pop:FindFirstChild("Zombies")
			local civs = pop:FindFirstChild("Civilians")
			if not zoms and not civs then return end

			-- gather dots + build the bucket grid
			local grid = {}
			local n = 0
			local dots = {}
			for _, folder in ipairs({ zoms, civs }) do
				if folder then
					for _, dot in ipairs(folder:GetChildren()) do
						if dot:IsA("BasePart") then
							local p = dot.Position
							local k = math.floor(p.X / cell) .. ":" .. math.floor(p.Z / cell)
							local arr = grid[k]
							if not arr then
								arr = {}
								grid[k] = arr
							end
							arr[#arr + 1] = { dot, p.X, p.Z }
							n = n + 1
							dots[#dots + 1] = arr[#arr]
						end
					end
				end
			end
			if n == 0 then return end

			for i = 1, n do
				local entry = dots[i]
				local dot = entry[1]
				local x, z = entry[2], entry[3]
				local cx = math.floor(x / cell)
				local cz = math.floor(z / cell)
				local count = 0
				for gx = cx - 1, cx + 1 do
					for gz = cz - 1, cz + 1 do
						local arr = grid[gx .. ":" .. gz]
						if arr then
							for j = 1, #arr do
								local o = arr[j]
								if o[1] ~= dot then
									local dx, dz = x - o[2], z - o[3]
									if dx * dx + dz * dz < rSq then
										count = count + 1
									end
								end
							end
						end
					end
				end
				local t = math.min(count / cfg.Cap, 1) * cfg.MaxT
				local base = baseColors[dot]
				if not base then
					base = dot.Color
					baseColors[dot] = base
				end
				if t > 0.01 then
					dot.Color = base:Lerp(WHITE, t)
				else
					dot.Color = base
				end
			end
		end)
	end)
end

return Density
