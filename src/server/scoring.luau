-- Score, prep budget, command points and end-of-round detection.
-- The score that matters is civilians saved, not zombies killed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.config)

local Scoring = {}

local setAttr
local remotes
local sim
local population
local onFinish

local saved, lost, kills
local cp
local prepSpent = 0
local totalCivs = 0
local waveTimes = {}
local finished = false

local function finish(reason)
	if finished then return end
	finished = true
	local ratio = totalCivs > 0 and saved / totalCivs or 0
	local grade = "D"
	if ratio >= 0.85 then
		grade = "S"
	elseif ratio >= 0.7 then
		grade = "A"
	elseif ratio >= 0.5 then
		grade = "B"
	elseif ratio >= 0.3 then
		grade = "C"
	end
	remotes.send({
		kind = "results",
		saved = saved,
		lost = lost,
		kills = kills,
		total = totalCivs,
		grade = grade,
		reason = reason,
	})
	if onFinish then onFinish() end
end

function Scoring.boot(deps)
	setAttr = deps.setAttr
	remotes = deps.remotes
	sim = deps.sim
	population = deps.population
	onFinish = deps.onFinish
end

function Scoring.newRound(total)
	totalCivs = total
	saved, lost, kills = 0, 0, 0
	cp = Config.CommandPoints.Start
	prepSpent = 0
	finished = false
	waveTimes = {}
	setAttr("Saved", 0)
	setAttr("Lost", 0)
	setAttr("Kills", 0)
	setAttr("CiviliansTotal", total)
	setAttr("CommandPoints", cp)
	setAttr("CPMax", Config.CommandPoints.Max)
	setAttr("PrepBudget", Config.Prep.Budget)
end

function Scoring.bump(field, n)
	if field == "Saved" then
		saved = saved + n
		setAttr("Saved", saved)
	elseif field == "Lost" then
		lost = lost + n
		setAttr("Lost", lost)
	elseif field == "Kills" then
		kills = kills + n
		setAttr("Kills", kills)
	end
end

function Scoring.trySpendPrep(cost)
	if prepSpent + cost > Config.Prep.Budget then
		return false
	end
	prepSpent = prepSpent + cost
	setAttr("PrepBudget", Config.Prep.Budget - prepSpent)
	return true
end

function Scoring.trySpendCP(cost)
	if cp < cost then
		return false
	end
	cp = cp - cost
	setAttr("CommandPoints", cp)
	return true
end

function Scoring.setWaveTimes(times)
	waveTimes = times
end

function Scoring.startWatch()
	sim.every(Config.CommandPoints.RegenInterval, function()
		if cp < Config.CommandPoints.Max then
			cp = cp + 1
			setAttr("CommandPoints", cp)
		end
	end)
	sim.every(1, function()
		if saved + lost >= totalCivs then
			finish("Все гражданские эвакуированы или потеряны")
		elseif sim.now() > Config.Simulation.TimeLimit then
			finish("Время вышло")
		end
	end)
end

return Scoring
