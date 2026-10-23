-- HUD: phase/timer, budgets, score, tool bar, pause/speed, toasts,
-- announcements and the results screen. Built entirely from code.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("config"))

local Input = require(script.Parent.input)

local Hud = {}

local state
local commandEvent
local eventEvent

local phaseLabel, statsLabel, scoreLabel
local pauseButton, speedButton, startButton
local toolButtons = {} -- [id] = { btn, main, stroke }; Instances cannot hold custom fields
local toastHolder, announceLabel, diagLabel
local resultsOverlay, resultsTitle, resultsGrade, resultsStats, resultsReason
local lastAnnounceAt = 0

local UI_BG = Color3.fromRGB(10, 12, 18)
local UI_STROKE = Color3.fromRGB(34, 42, 56)
local UI_TEXT = Color3.fromRGB(214, 224, 232)
local UI_DIM = Color3.fromRGB(126, 138, 156)
local ACCENT = Color3.fromRGB(61, 224, 132) -- radar green
local GOOD = Color3.fromRGB(46, 204, 113)
local BAD = Color3.fromRGB(255, 84, 84)

local function mk(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local function panel(parent, size, pos, anchor)
	local f = mk("Frame", {
		Size = size,
		Position = pos,
		AnchorPoint = anchor or Vector2.new(0, 0),
		BackgroundColor3 = UI_BG,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
	}, parent)
	mk("UICorner", { CornerRadius = UDim.new(0, 10) }, f)
	mk("UIStroke", { Color = UI_STROKE, Thickness = 1.5 }, f)
	return f
end

local function label(parent, props)
	local defaults = {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		TextSize = 15,
		TextColor3 = UI_TEXT,
		Text = "",
	}
	for k, v in pairs(props) do
		defaults[k] = v
	end
	return mk("TextLabel", defaults, parent)
end

local function attr(n)
	return state:GetAttribute(n)
end

-- toasts ------------------------------------------------------------------

local function toast(text, tone)
	local color = UI_TEXT
	if tone == "bad" then
		color = BAD
	elseif tone == "good" then
		color = GOOD
	end
	local item = label(toastHolder, {
		Size = UDim2.new(0, 0, 0, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = text,
		TextColor3 = color,
		TextSize = 15,
	})
	local pad = mk("UIPadding", {}, item)
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	local bg = mk("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		ZIndex = -1,
		BackgroundColor3 = UI_BG,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
	}, item)
	mk("UICorner", { CornerRadius = UDim.new(0, 8) }, bg)

	local children = toastHolder:GetChildren()
	local count = 0
	for _, c in ipairs(children) do
		if c:IsA("TextLabel") then
			count = count + 1
		end
	end
	if count > 5 then
		for _, c in ipairs(children) do
			if c:IsA("TextLabel") then
				c:Destroy()
				break
			end
		end
	end
	task.delay(4.5, function()
		if item.Parent then
			item:Destroy()
		end
	end)
end

local function announce(text, dur)
	announceLabel.Text = text
	announceLabel.TextTransparency = 0
	announceLabel.TextStrokeTransparency = 0.4
	lastAnnounceAt = os.clock()
	task.delay(dur or 2.5, function()
		if os.clock() - lastAnnounceAt >= (dur or 2.5) - 0.01 then
			announceLabel.Text = ""
		end
	end)
end

-- results -----------------------------------------------------------------

local function showResults(r)
	resultsTitle.Text = "РАУНД ЗАВЕРШЁН"
	resultsGrade.Text = r.grade or "-"
	local gradeColor = UI_DIM
	if r.grade == "S" then
		gradeColor = Color3.fromRGB(255, 215, 80)
	elseif r.grade == "A" then
		gradeColor = GOOD
	elseif r.grade == "B" then
		gradeColor = ACCENT
	elseif r.grade == "C" then
		gradeColor = UI_TEXT
	else
		gradeColor = BAD
	end
	resultsGrade.TextColor3 = gradeColor
	resultsStats.Text = "Спасено: " .. (r.saved or 0) .. " из " .. (r.total or 0)
		.. "\nПотери: " .. (r.lost or 0) .. "   •   Уничтожено зомби: " .. (r.kills or 0)
	resultsReason.Text = r.reason or ""
	resultsOverlay.Visible = true
end

-- refresh -----------------------------------------------------------------

local function refreshToolbar()
	local ph = attr("Phase")
	for _, info in ipairs(Config.toolInfo()) do
		local rec = toolButtons[info.id]
		if rec then
			local active = Input.getTool() == info.id
			local enabled = ph == info.phase
			rec.btn.BackgroundTransparency = enabled and 0.08 or 0.35
			rec.main.TextTransparency = enabled and 0 or 0.5
			rec.stroke.Color = active and ACCENT or UI_STROKE
			rec.stroke.Thickness = active and 2.5 or 1.5
		end
	end
end

local function refresh()
	local ph = attr("Phase") or "Boot"
	if ph == "Planning" then
		local left = math.ceil(attr("PrepCountdown") or 0)
		phaseLabel.Text = "🛡 ПОДГОТОВКА · " .. left .. " с"
		phaseLabel.TextColor3 = ACCENT
		startButton.Visible = true
	elseif ph == "Live" then
		local paused = attr("Paused")
		if paused then
			phaseLabel.Text = "⏸ ПАУЗА · Space"
			phaseLabel.TextColor3 = Color3.fromRGB(255, 215, 80)
		else
			phaseLabel.Text = "☣ СИМУЛЯЦИЯ · x" .. (attr("Speed") or 1)
			phaseLabel.TextColor3 = BAD
		end
		startButton.Visible = false
	else
		phaseLabel.Text = "🏁 РАУНД ЗАВЕРШЁН"
		phaseLabel.TextColor3 = GOOD
		startButton.Visible = false
	end

	statsLabel.Text = "🧱 " .. (attr("PrepBudget") or 0)
		.. "    ⚡ " .. (attr("CommandPoints") or 0) .. "/" .. (attr("CPMax") or 0)
	scoreLabel.Text = "Спасено " .. (attr("Saved") or 0) .. "/" .. (attr("CiviliansTotal") or 0)
		.. "    Потери " .. (attr("Lost") or 0)
		.. "    Цели " .. (attr("Kills") or 0)
		.. "    🧟 " .. (attr("ZombiesAlive") or 0)

	if ph == "Live" then
		pauseButton.Text = attr("Paused") and "▶" or "⏸"
		speedButton.Text = "x" .. (attr("Speed") or 1)
	else
		pauseButton.Text = "⏸"
		speedButton.Text = "x1"
	end

	refreshToolbar()

	local errText = attr("LastError")
	if errText then
		diagLabel.Text = "Sturdy Dollop v" .. (Config.Version or "?") .. "  •  ОШИБКА: " .. errText
		diagLabel.TextColor3 = BAD
	else
		diagLabel.Text = "Sturdy Dollop v" .. (Config.Version or "?") .. "  •  ок"
		diagLabel.TextColor3 = UI_DIM
	end
end

-- init --------------------------------------------------------------------

function Hud.init(cityData)
	state = ReplicatedStorage:WaitForChild(Config.Net.StateFolder)
	local remotesFolder = ReplicatedStorage:WaitForChild(Config.Net.RemotesFolder)
	commandEvent = remotesFolder:WaitForChild(Config.Net.Command)
	eventEvent = remotesFolder:WaitForChild(Config.Net.Event)

	local gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- top center: phase
	local top = panel(gui, UDim2.new(0, 380, 0, 44), UDim2.new(0.5, 0, 0, 10), Vector2.new(0.5, 0))
	phaseLabel = label(top, {
		Size = UDim2.new(1, -20, 1, 0),
		Position = UDim2.new(0, 10, 0, 0),
		Font = Enum.Font.GothamBold,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	-- top left: budgets
	local stats = panel(gui, UDim2.new(0, 260, 0, 44), UDim2.new(0, 12, 0, 10))
	statsLabel = label(stats, {
		Size = UDim2.new(1, -16, 1, 0),
		Position = UDim2.new(0, 8, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	-- top right: score
	local score = panel(gui, UDim2.new(0, 420, 0, 44), UDim2.new(1, -12, 0, 10), Vector2.new(1, 0))
	scoreLabel = label(score, {
		Size = UDim2.new(1, -16, 1, 0),
		Position = UDim2.new(0, 8, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 14,
	})

	-- toasts + announcements
	toastHolder = mk("Frame", {
		Size = UDim2.new(0, 700, 0, 0),
		Position = UDim2.new(0.5, 0, 0, 64),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, gui)
	mk("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	}, toastHolder)

	diagLabel = label(gui, {
		Size = UDim2.new(0, 620, 0, 32),
		Position = UDim2.new(0, 12, 1, -30),
		AnchorPoint = Vector2.new(0, 1),
		Text = "Sturdy Dollop v" .. Config.Version .. "  •  ок",
		TextSize = 12,
		TextColor3 = UI_DIM,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
	})

	announceLabel = label(gui, {
		Size = UDim2.new(1, 0, 0, 40),
		Position = UDim2.new(0, 0, 0, 130),
		AnchorPoint = Vector2.new(0.5, 0),
		Font = Enum.Font.GothamBold,
		TextSize = 30,
		TextStrokeTransparency = 0.4,
	})

	-- bottom toolbar
	local bar = mk("Frame", {
		Size = UDim2.new(0, 830, 0, 74),
		Position = UDim2.new(0.5, 0, 1, -14),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, gui)
	mk("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	}, bar)

	for _, info in ipairs(Config.toolInfo()) do
		local btn = mk("TextButton", {
			Size = UDim2.new(0, 108, 0, 64),
			BackgroundColor3 = UI_BG,
			BackgroundTransparency = 0.08,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = true,
			LayoutOrder = info.key.Value,
		}, bar)
		mk("UICorner", { CornerRadius = UDim.new(0, 10) }, btn)
		local stroke = mk("UIStroke", { Color = UI_STROKE, Thickness = 1.5 }, btn)
		local main = label(btn, {
			Size = UDim2.new(1, 0, 0, 34),
			Position = UDim2.new(0, 0, 0, 4),
			Text = info.icon .. " " .. info.name,
			TextSize = 15,
			Font = Enum.Font.GothamBold,
		})
		local sub = label(btn, {
			Size = UDim2.new(1, 0, 0, 20),
			Position = UDim2.new(0, 0, 0, 38),
			Text = info.cost .. (info.phase == "Planning" and " 🧱" or " ⚡") .. "  [" .. info.key.Name .. "]",
			TextSize = 12,
			TextColor3 = UI_DIM,
		})
		toolButtons[info.id] = { btn = btn, main = main, stroke = stroke }
		btn.MouseButton1Click:Connect(function()
			Input.setTool(info.id)
		end)
	end

	pauseButton = mk("TextButton", {
		Size = UDim2.new(0, 56, 0, 64),
		BackgroundColor3 = UI_BG,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		Text = "⏸",
		TextSize = 20,
		Font = Enum.Font.GothamBold,
		TextColor3 = UI_TEXT,
		LayoutOrder = 90,
	}, bar)
	mk("UICorner", { CornerRadius = UDim.new(0, 10) }, pauseButton)
	pauseButton.MouseButton1Click:Connect(function()
		if (attr("Phase")) == "Live" then
			commandEvent:FireServer({ type = "pause" })
		end
	end)

	speedButton = mk("TextButton", {
		Size = UDim2.new(0, 56, 0, 64),
		BackgroundColor3 = UI_BG,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		Text = "x1",
		TextSize = 18,
		Font = Enum.Font.GothamBold,
		TextColor3 = UI_TEXT,
		LayoutOrder = 91,
	}, bar)
	mk("UICorner", { CornerRadius = UDim.new(0, 10) }, speedButton)
	speedButton.MouseButton1Click:Connect(function()
		if (attr("Phase")) == "Live" then
			commandEvent:FireServer({ type = "speed" })
		end
	end)

	-- start button (bottom right)
	startButton = mk("TextButton", {
		Size = UDim2.new(0, 250, 0, 50),
		Position = UDim2.new(1, -16, 1, -16),
		AnchorPoint = Vector2.new(1, 1),
		BackgroundColor3 = Color3.fromRGB(16, 68, 44),
		BorderSizePixel = 0,
		Text = "▶  НАЧАТЬ СИМУЛЯЦИЮ",
		TextSize = 16,
		Font = Enum.Font.GothamBold,
		TextColor3 = UI_TEXT,
	}, gui)
	mk("UICorner", { CornerRadius = UDim.new(0, 10) }, startButton)
	startButton.MouseButton1Click:Connect(function()
		commandEvent:FireServer({ type = "start" })
	end)

	-- results overlay
	resultsOverlay = mk("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 10,
	}, gui)
	local card = panel(resultsOverlay, UDim2.new(0, 440, 0, 400), UDim2.new(0.5, 0, 0.5, 0), Vector2.new(0.5, 0.5))
	card.ZIndex = 11
	resultsTitle = label(card, {
		Size = UDim2.new(1, -30, 0, 36),
		Position = UDim2.new(0, 15, 0, 24),
		Font = Enum.Font.GothamBold,
		TextSize = 24,
		ZIndex = 12,
	})
	resultsGrade = label(card, {
		Size = UDim2.new(1, -30, 0, 90),
		Position = UDim2.new(0, 15, 0, 66),
		Font = Enum.Font.GothamBold,
		TextSize = 72,
		ZIndex = 12,
	})
	resultsStats = label(card, {
		Size = UDim2.new(1, -30, 0, 70),
		Position = UDim2.new(0, 15, 0, 168),
		TextSize = 17,
		TextColor3 = UI_TEXT,
		ZIndex = 12,
	})
	resultsReason = label(card, {
		Size = UDim2.new(1, -30, 0, 40),
		Position = UDim2.new(0, 15, 0, 240),
		TextSize = 14,
		TextColor3 = UI_DIM,
		TextWrapped = true,
		ZIndex = 12,
	})
	local again = mk("TextButton", {
		Size = UDim2.new(0, 220, 0, 48),
		Position = UDim2.new(0.5, 0, 1, -68),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.fromRGB(16, 68, 44),
		BorderSizePixel = 0,
		Text = " Играть снова (новый город)",
		TextSize = 15,
		Font = Enum.Font.GothamBold,
		TextColor3 = UI_TEXT,
		ZIndex = 12,
	}, card)
	mk("UICorner", { CornerRadius = UDim.new(0, 10) }, again)
	again.MouseButton1Click:Connect(function()
		resultsOverlay.Visible = false
		commandEvent:FireServer({ type = "restart" })
	end)

	-- events
	eventEvent.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then return end
		if payload.kind == "toast" then
			toast(payload.text, payload.tone)
		elseif payload.kind == "announce" then
			announce(payload.text, payload.dur)
		elseif payload.kind == "results" then
			showResults(payload)
		end
	end)

	state:GetAttributeChangedSignal("Phase"):Connect(function()
		if attr("Phase") ~= "Done" then
			resultsOverlay.Visible = false
		end
	end)

	-- refresh loop
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc = acc + dt
		if acc >= 0.12 then
			acc = 0
			refresh()
		end
	end)
	refresh()
end

return Hud
