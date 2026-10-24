-- Drag 2D: конфигурация. Весь баланс здесь.

local Config = {}

Config.Version = "0.7.0"

Config.Economy = {
	StartCash = 500,
	BaseReward = 100,      -- за любой завершённый заезд
	WinBonus = 150,        -- за победу над соперником
	ReactionBonus = 60,    -- реакция < ReactionGreat на старте
	ReactionGreat = 0.25,  -- сек
}

Config.Race = {
	DistanceM = 402.3,     -- 1/4 мили
	StudsPerMeter = 3.57,
	StartZ = -30,          -- где стоят машины
	TreeSteps = 3,         -- амбры
	TreeInterval = 0.5,    -- сек между амбрами
	GreenHold = 6,
	PlayerLaneTop = 2,     -- верх полосы игрока (Y), ИИ выше на экране
	LaneGap = 13,          -- вертикальный зазор между полосами
}

-- Двигатель (единственный источник правды; тюнинг v0.8+ будет править эти
-- числа: УОЗ подвинет кривую момента и т.д.)
Config.Engine = {
	IdleRPM = 1000, IdleTorque = 315, IdleShape = 0.275,
	PeakRPM = 2500, PeakTorque = 390,
	Redline = 7500, RedlineTorque = 160, RedShape = 0.31,
	ShiftRPM = 7000, DownshiftRPM = 3850,
	GearRatios = { 3.2, 2.1, 1.55, 1.2, 0.95 },
	FinalDrive = 3.6,
	TorqueScale = 1.2, -- масштаб тяги (калибруется под массу)
	DirSign = -1,      -- знак вращения колеса (поедет назад — поменять знак)
}

-- Геометрия/физика 2D-машины: кузов-пластина + 2 колеса-цилиндра на хинжах
Config.Car2D = {
	WheelRadius = 1.6,
	WheelWidth = 0.9,
	BodyLength = 14, BodyHeight = 4, BodyThickness = 0.4,
	FrontAxleZ = 4.2, RearAxleZ = -4.2,
	WheelDensity = 3, WheelFriction = 1.6,
	BodyDensity = 0.7,
	BrakeTorque = 26000,
	HoldTorque = 1500,   -- держит на месте без газа
	Drag = 0.0004,       -- аэросопротивление
}

-- Картинки (rbxassetid://...). Пусто = цветная заглушка с видимой спицей.
Config.Art = {
	PlayerBody = "",  -- картинка твоей машины (вид сбоку, нос влево!)
	PlayerWheel = "", -- картинка колеса (диск/шина, круг)
	AIBody = "",
	AIWheel = "",
}

Config.Net = {
	StateFolder = "GameState",
	RemotesFolder = "Remotes",
}

Config.Colors = {
	Asphalt = "2B2F38",
	Line = "C9D2E4",
	Ground = "161A23",
	Sky = "27344A",
	SkyLow = "4A5A78",
	FarBand = "1B2434",
	NearBand = "121826",
	Car1 = "D64545",
	Car2 = "3D7BD9",
}

function Config.color(name)
	return Color3.fromHex(Config.Colors[name])
end

-- Спецификация для Drivetrain (shared/drivetrain — проверен headless-тестом)
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

return Config
