-- Entry point: boots rounds, owns the phase machine and routes commands.
--
-- Round flow: Planning (build your defense, real-time countdown, no zombies)
-- -> Live (simulation runs, air support only, pause/speed available)
-- -> Done (results screen, restart with a fresh city).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.config)
local MapGen = require(ReplicatedStorage.Shared.mapgen)

local Sim = require(script.sim)
local Remotes = require(script.remotes)
local City = require(script.city)
local Units = require(script.units)
local Population = require(script.population)
local Strikes = require(script.strikes)
local Scoring = require(script.scoring)

Players.CharacterAutoLoads = false -- top-down strategy: no avatars

-- flat "navigation app" lighting
local Lighting = game:GetService("Lighting")
Lighting.ClockTime = 14.2
Lighting.Brightness = 2.4
Lighting.Ambient = Color3.fromRGB(120, 130, 150)
Lighting.OutdoorAmbient = Color3.fromRGB(140, 148, 165)
Lighting.GlobalShadows = true
Lighting.FogEnd = 100000

-- shared state ------------------------------------------------------------
local state = Instance.new("Folder")
state.Name = Config.Net.StateFolder
state.Parent = ReplicatedStorage

local function setAttr(name, value)
	state:SetAttribute(name, value)
end

local function getAttr(name)
	return state:GetAttribute(name)
end

setAttr("Phase", "Boot")
setAttr("Version", Config.Version)

local phase = "Boot"
local roundId = 0
local cityRef = nil

local function setPhase(p)
	phase = p
	setAttr("Phase", p)
end

-- module wiring -----------------------------------------------------------
Sim.bindState(setAttr)
Remotes.init()
Remotes.watch()

Scoring.boot({
	setAttr = setAttr,
	remotes = Remotes,
	sim = Sim,
	population = Population,
	onFinish = function()
		setPhase("Done")
		Sim.freeze()
	end,
})
Strikes.boot({
	remotes = Remotes,
	sim = Sim,
	units = Units,
	population = Population,
	scoring = Scoring,
	cityModule = City,
})
Units.boot({
	setAttr = setAttr,
	remotes = Remotes,
	scoring = Scoring,
	population = Population,
})
Population.boot({
	cityModule = City,
	units = Units,
	scoring = Scoring,
	remotes = Remotes,
	setAttr = setAttr,
})

-- round flow --------------------------------------------------------------

local function startLive()
	if phase ~= "Planning" then return end
	setPhase("Live")
	Population.beginSim()
	Remotes.send({ kind = "announce", text = "СИМУЛЯЦИЯ ЗАПУЩЕНА", dur = 2.5 })

	local waveTimes = {}
	for wi, w in ipairs(Config.Simulation.Waves) do
		waveTimes[#waveTimes + 1] = w.t
		local point = cityRef.outbreakPoints[math.min(wi, #cityRef.outbreakPoints)]
		local count = w.count
		Sim.after(math.max(w.t - Config.Simulation.WaveTelegraph, 0.01), function()
			Population.showTelegraph(point, false)
			Remotes.send({
				kind = "announce",
				text = "⚠️ Вспышка: сектор " .. cityRef.sectorName(point) .. " — " .. count .. " заражённых",
				dur = 3,
			})
		end)
		Sim.after(math.max(w.t, 0.01), function()
			Population.spawnWave(point, count)
		end)
	end
	Scoring.setWaveTimes(waveTimes)
	Scoring.startWatch()
end

local function startRound()
	roundId = roundId + 1
	Sim.reset()
	City.destroyAll()

	local seed = math.random(1, 2 ^ 30 - 1)
	setAttr("Seed", seed)
	cityRef = MapGen.generate(seed)
	local folders = City.build(cityRef)

	Units.newRound(cityRef, folders)
	Population.newRound(cityRef, folders)
	Strikes.newRound(cityRef)
	Scoring.newRound(#cityRef.civSpawns)

	Units.addDefaultEvac(cityRef.evacNode)
	Population.showTelegraph(cityRef.outbreakPoints[1], true)

	setPhase("Planning")
	setAttr("PrepCountdown", Config.Prep.Duration)
	Remotes.send({
		kind = "toast",
		text = "Первая вспышка: сектор " .. cityRef.sectorName(cityRef.outbreakPoints[1])
			.. ". Обустрой оборону до конца подготовки.",
		tone = "info",
	})
	Remotes.send({ kind = "announce", text = "ПОДГОТОВКА", dur = 2 })

	task.spawn(function()
		local myRound = roundId
		while phase == "Planning" and roundId == myRound do
			task.wait(1)
			if phase ~= "Planning" or roundId ~= myRound then return end
			local left = (getAttr("PrepCountdown") or 0) - 1
			setAttr("PrepCountdown", math.max(left, 0))
			if left <= 0 then
				startLive()
			end
		end
	end)
end

-- command router ----------------------------------------------------------

Remotes.setHandler(function(player, cmd)
	if typeof(cmd) ~= "table" then return end
	local kind = cmd.type
	if kind == "start" then
		if phase == "Planning" then
			startLive()
		end
	elseif kind == "pause" then
		if phase == "Live" then
			Sim.togglePause()
		end
	elseif kind == "speed" then
		if phase == "Live" then
			Sim.cycleSpeed()
		end
	elseif kind == "place" then
		if phase == "Planning" and typeof(cmd.x) == "number" and typeof(cmd.z) == "number" then
			local ok, err = Units.place(cmd.tool, cmd.x, cmd.z)
			if not ok then
				Remotes.sendTo(player, { kind = "toast", text = err, tone = "bad" })
			end
		end
	elseif kind == "strike" then
		if phase == "Live" and typeof(cmd.x) == "number" and typeof(cmd.z) == "number" then
			local ok, err = Strikes.order(cmd.kind, cmd.x, cmd.z)
			if not ok then
				Remotes.sendTo(player, { kind = "toast", text = err, tone = "bad" })
			end
		end
	elseif kind == "restart" then
		if phase == "Done" then
			task.spawn(startRound)
		end
	end
end)

-- main loop ---------------------------------------------------------------

RunService.Heartbeat:Connect(function(dt)
	local sdt = Sim.advance(dt)
	if sdt > 0 then
		local ok, err = pcall(function()
			Population.update(sdt)
			Units.update(sdt)
		end)
		if not ok then
			-- self-diagnostics: surface the failure on the HUD, keep the loop alive
			warn("sim tick error: " .. tostring(err))
			setAttr("LastError", "sim: " .. tostring(err))
		end
	end
end)

startRound()
