-- Headless-тест трансмиссии: кривая момента, передачи, пересчёт оборотов.
-- Запуск: node tests/harness.mjs . tests/drivetrain_test.luau

local Drivetrain = require(game:GetService("ReplicatedStorage").Shared.drivetrain)

-- запасной движок (числа — дефолты A-Chassis Tune)
local e = {
	idleRpm = 1000, idleTorque = 315, idleShape = 0.275,
	peakRpm = 2500, peakTorque = 390,
	redline = 7500, redlineTorque = 160, redShape = 0.31,
	shiftRpm = 7000, gearCount = 5, finalDrive = 3.6,
}

local function near(a, b, eps)
	return math.abs(a - b) < (eps or 1e-6)
end

-- опорные точки кривой
assert(near(Drivetrain.torqueAt(e, 500), 315), "ниже холостых момент должен быть холостым")
assert(near(Drivetrain.torqueAt(e, 1000), 315), "на холостых = IdleTorque")
assert(near(Drivetrain.torqueAt(e, 2500), 390), "на пике = PeakTorque")
assert(near(Drivetrain.torqueAt(e, 7500), 160), "на отсечке = RedlineTorque")
assert(near(Drivetrain.torqueAt(e, 7600), 0), "за отсечкой топлива нет")

-- кривая монотонно растёт до пика
local prev = -1
for rpm = 1000, 2500, 50 do
	local tq = Drivetrain.torqueAt(e, rpm)
	assert(tq >= prev - 1e-9, "кривая проваливается до пика на " .. rpm)
	prev = tq
end

-- ЯДРО ДИЗАЙНА: ручная коробка выгодна только через пик кривой —
-- удельная тяга (момент/обороты) на пике выше, чем на перекруте.
local specificAtPeak = Drivetrain.torqueAt(e, 2500) / 2500
local specificOverrev = Drivetrain.torqueAt(e, 6500) / 6500
assert(specificAtPeak > specificOverrev, "пик кривой должен быть выгоднее перекрута")

-- авто-переключение: вверх на shiftRpm, вниз на 55%
assert(near(Drivetrain.autoShift(e, 1, 6999), 1), "до shiftRpm не вверх")
assert(near(Drivetrain.autoShift(e, 1, 7000), 2), "на shiftRpm вверх")
assert(near(Drivetrain.autoShift(e, 3, 3851), 3), "выше 55% — держим передачу")
assert(near(Drivetrain.autoShift(e, 3, 3850), 2), "55% и ниже — вниз")
assert(near(Drivetrain.autoShift(e, 5, 7000), 5), "верхняя передача — вверх некуда")

-- пересчёт оборотов туда-обратно без потерь
local rps = 7
assert(near(Drivetrain.rpmFromWheel(rps, 3.2, 3.6), rps * 3.2 * 3.6 * 9.5493, 0.01))
assert(near(Drivetrain.wheelFromRpm(Drivetrain.rpmFromWheel(rps, 2, 3), 2, 3), rps))

-- момент на ведущее колесо делится между ними; газ масштабирует
local perTwo = Drivetrain.wheelTorque(e, 2500, 3.2, 2, 1, 1)
local perOne = Drivetrain.wheelTorque(e, 2500, 3.2, 1, 1, 1)
assert(near(perTwo * 2, perOne), "момент делится между ведущими")
assert(near(Drivetrain.wheelTorque(e, 2500, 3.2, 2, 0, 1), 0), "без газа момента нет")
assert(near(Drivetrain.wheelTorque(e, 8000, 3.2, 2, 1, 1), 0), "за отсечкой тяги нет")

-- нормированный момент в пределах [0..1]
assert(Drivetrain.torqueNorm(e, 2500) == 1)
assert(Drivetrain.torqueNorm(e, 7600) == 0)
assert(Drivetrain.torqueNorm(e, 1000) < 1)

log("drivetrain_test: OK — кривая, передачи, обороты, разделение момента")
