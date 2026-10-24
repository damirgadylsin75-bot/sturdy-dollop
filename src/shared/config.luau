-- Drag II: конфигурация игры. Весь баланс здесь.

local Config = {}

Config.Version = "0.6.2"

Config.Economy = {
	StartCash = 500,
	BaseReward = 100,      -- за любой завершённый заезд
	WinBonus = 150,        -- за победу над соперником
	ReactionBonus = 60,    -- реакция < ReactionGreat на старте
	ReactionGreat = 0.25,  -- сек
}

Config.Race = {
	DistanceM = 402.3,     -- 1/4 мили
	StudsPerMeter = 3.57,  -- роблокс-стады на метр (наш масштаб трека)
	LaneWidth = 26,        -- стад между центрами полос
	StartZ = -30,          -- где стоят машины на старте (стад по Z)
	CarYawDeg = 180,       -- разворот модели машины, если смотрит не вдоль трека
	TreeSteps = 3,         -- амбры
	TreeInterval = 0.5,    -- сек между амбрами
	GreenHold = 6,         -- сек зелёного до «уехал сам»
	JumpStartDQ = true,    -- старт до зелёного = дисквалификация
}

-- Схема тюнинга (применяется к A-Chassis Tune при спавне; в v0.1 только макет)
Config.Tuning = {
	IgnitionAdvance = { min = 5, max = 45, default = 18, unit = "°" }, -- УОЗ
	FinalDrive = { min = 2.6, max = 5.4, default = 3.6, unit = "" },
	TireGrip = { min = 0.8, max = 1.6, default = 1.1, unit = "g" },
	DriveTorqueScale = 4, -- масштаб тяги под массу модели (калибруется)
}

Config.Net = {
	StateFolder = "GameState",
	RemotesFolder = "Remotes",
}

Config.Colors = {
	Asphalt = "2B2F38",
	Line = "C9D2E4",
	Ground = "161A23",
	Car1 = "D64545",
	Car2 = "3D7BD9",
}


-- Двигатель НАШЕГО шасси (единственный источник правды; тюнинг v0.7+ будет
-- править именно эти числа — УОЗ подвинет кривую момента и т.д.)
Config.Engine = {
	IdleRPM = 1000, IdleTorque = 315, IdleShape = 0.275,
	PeakRPM = 2500, PeakTorque = 390,
	Redline = 7500, RedlineTorque = 160, RedShape = 0.31,
	ShiftRPM = 7000, DownshiftRPM = 3850,
	GearRatios = { 3.2, 2.1, 1.55, 1.2, 0.95 },
	FinalDrive = 3.6,
	TorqueScale = 2, -- масштаб тяги под массу шасси
}

-- Геометрия/физика нашего шасси
Config.Chassis = {
	WheelDiameter = 3.2, WheelWidth = 1.2,
	Width = 8, Height = 1.2, Length = 16,
	Clearance = 0.7,     -- клиренс (низ кузова над землёй)
	BodyLift = 0.15,     -- насколько кузов поднят над рамой
	DirSign = -1,        -- знак вращения колёс (поедет назад — поменять на 1)
	Drag = 0.0004,       -- аэросопротивление (меньше = выше максималка)
	BrakeTorque = 25000,
	HoldTorque = 2000,   -- держит машину на месте без газа
	StabilizeTorque = 5e6, -- не даёт опрокинуться (драг: руль не нужен)
}

function Config.engineSpec()
	local E = Config.Engine
	return {
		idleRpm = E.IdleRPM, idleTorque = E.IdleTorque, idleShape = E.IdleShape,
		peakRpm = E.PeakRPM, peakTorque = E.PeakTorque,
		redline = E.Redline, redlineTorque = E.RedlineTorque, redShape = E.RedShape,
		shiftRpm = E.ShiftRPM, downshiftRpm = E.DownshiftRPM,
		gearCount = #E.GearRatios, finalDrive = E.FinalDrive,
	}
end

function Config.color(name)
	return Color3.fromHex(Config.Colors[name])
end

return Config
