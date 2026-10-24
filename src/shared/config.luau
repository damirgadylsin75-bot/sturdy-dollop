-- Drag II: конфигурация игры. Весь баланс здесь.

local Config = {}

Config.Version = "0.2.0"

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
	CarYawDeg = 0,         -- разворот модели машины, если смотрит не вдоль трека
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

function Config.color(name)
	return Color3.fromHex(Config.Colors[name])
end

return Config
