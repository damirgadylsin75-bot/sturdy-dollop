-- Fixed-step simulation clock with pause, speed multiplier and a sim-time
-- scheduler. Everything gameplay-related is scheduled on this clock, so
-- pausing freezes the whole battle, including pending airstrikes.

local Sim = {}

local publishState = nil
local now = 0
local timeScale = 1
local paused = false
local timers = {} -- { t = simTime, fn }
local loops = {}  -- { interval, next, fn }

local FIXED_DT = 1 / 30
local accumulator = 0

function Sim.bindState(setter)
	publishState = setter
end

function Sim.reset()
	now = 0
	timeScale = 1
	paused = false
	timers = {}
	loops = {}
	accumulator = 0
	if publishState then
		publishState("Paused", false)
		publishState("Speed", 1)
		publishState("SimTime", 0)
	end
end

function Sim.now()
	return now
end

function Sim.isPaused()
	return paused
end

function Sim.after(delay, fn)
	timers[#timers + 1] = { t = now + delay, fn = fn }
end

function Sim.every(interval, fn)
	local job = { interval = interval, next = now + interval, fn = fn }
	loops[#loops + 1] = job
	return job
end

function Sim.cancel(job)
	for i = #loops, 1, -1 do
		if loops[i] == job then
			table.remove(loops, i)
		end
	end
end

function Sim.togglePause()
	paused = not paused
	if publishState then
		publishState("Paused", paused)
	end
	return paused
end

function Sim.freeze()
	paused = true
	if publishState then
		publishState("Paused", true)
	end
end

function Sim.cycleSpeed()
	if timeScale >= 4 then
		timeScale = 1
	elseif timeScale >= 2 then
		timeScale = 4
	else
		timeScale = 2
	end
	if publishState then
		publishState("Speed", timeScale)
	end
	return timeScale
end

function Sim.step()
	-- one-shot timers
	local i = 1
	while i <= #timers do
		local tm = timers[i]
		if tm.t <= now then
			table.remove(timers, i)
			tm.fn()
		else
			i = i + 1
		end
	end
	-- repeating jobs
	for _, job in ipairs(loops) do
		while job.next <= now do
			job.next = job.next + job.interval
			job.fn()
		end
	end
end

-- Advance the clock by real dt; returns the sim time actually consumed.
function Sim.advance(dtReal)
	if paused then
		return 0
	end
	accumulator = accumulator + math.min(dtReal, 0.25) * timeScale
	local consumed = 0
	while accumulator >= FIXED_DT do
		accumulator = accumulator - FIXED_DT
		consumed = consumed + FIXED_DT
		now = now + FIXED_DT
		Sim.step()
	end
	if consumed > 0 and publishState then
		publishState("SimTime", math.floor(now * 10) / 10)
	end
	return consumed
end

return Sim
