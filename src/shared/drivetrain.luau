-- Drivetrain: чистая математика трансмиссии драг-кара. Без Roblox API —
-- поэтому гоняется в headless-прогоне (tests/drivetrain_test.luau).
-- Значения приходят из Tune A-Chassis; здесь только физика.

local Drivetrain = {}

-- Спецификация двигателя (всё из Tune, с запасными значениями по умолчанию):
-- idleRpm, idleTorque, idleShape, peakRpm, peakTorque, redline,
-- redlineTorque, redShape, shiftRpm, downshiftRpm (опц.), gearCount,
-- finalDrive.

-- Кривая момента: idle → пик (форма idleShape) → redline (форма redShape),
-- за redline отсечка (0). Чем «круче» форма, тем резче набор момента.
function Drivetrain.torqueAt(e, rpm)
	if rpm <= e.idleRpm then
		return e.idleTorque
	end
	if rpm > e.redline then
		return 0 -- отсечка (на самой redline ещё тянем)
	end
	if rpm <= e.peakRpm then
		local a = (rpm - e.idleRpm) / (e.peakRpm - e.idleRpm)
		return e.idleTorque + (e.peakTorque - e.idleTorque) * a ^ e.idleShape
	end
	local a = (rpm - e.peakRpm) / (e.redline - e.peakRpm)
	return e.peakTorque + (e.redlineTorque - e.peakTorque) * a ^ e.redShape
end

-- Момент относительно пика [0..1]. Понадобится модели УОЗ (v0.4).
function Drivetrain.torqueNorm(e, rpm)
	if e.peakTorque <= 0 then return 0 end
	return math.max(0, Drivetrain.torqueAt(e, rpm) / e.peakTorque)
end

-- Обороты двигателя из скорости колеса (рад/с) через передачу и редуктор.
function Drivetrain.rpmFromWheel(wheelRadPerSec, gearRatio, finalDrive)
	return wheelRadPerSec * gearRatio * finalDrive * 9.5493 -- рад/с → об/мин
end

-- Обратно: обороты → скорость колеса (рад/с).
function Drivetrain.wheelFromRpm(rpm, gearRatio, finalDrive)
	return rpm / (gearRatio * finalDrive * 9.5493)
end

-- Авто-переключение: вверх на shiftRpm, вниз на downshiftRpm
-- (по умолчанию 55% от shiftRpm). На верхней передаче вверх некуда.
function Drivetrain.autoShift(e, gear, rpm)
	if gear >= 1 and gear < e.gearCount and rpm >= e.shiftRpm then
		return gear + 1
	end
	local down = e.downshiftRpm or (e.shiftRpm * 0.55)
	if gear > 1 and rpm <= down then
		return gear - 1
	end
	return gear
end

-- Момент на ОДНО ведущее колесо (lb-ft на хинж-мотор A-Chassis).
-- efficiency — потери в трансмиссии.
function Drivetrain.wheelTorque(e, rpm, gearRatio, drivenCount, throttle, efficiency)
	local tq = Drivetrain.torqueAt(e, rpm) * throttle
	local total = tq * gearRatio * e.finalDrive * (efficiency or 0.85)
	return total / math.max(1, drivenCount)
end

return Drivetrain
