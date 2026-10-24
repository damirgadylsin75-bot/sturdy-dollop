-- CarPhysics: превращает витринную модель (держится якорями, физики нет)
-- в физическую машину. НИЧЕГО не удаляет: декор приваривается к корню,
-- якоря снимаются, колёсам создаются мотор-хинжи (#AV), курс держится
-- ровно. Всё происходит на КОПИИ при спавне — оригинал не тронут.

local CarPhysics = {}

local WHEEL_NAMES = { FL = true, FR = true, RL = true, RR = true }

local function volume(p)
	return p.Size.X * p.Size.Y * p.Size.Z
end

function CarPhysics.build(car)
	local wheelsFolder = car:FindFirstChild("Wheels")

	-- привод из Tune (какие колёса ведущие)
	local config = "RWD"
	local tuneModule = car:FindFirstChild("A-Chassis Tune", true)
	if tuneModule then
		local ok, t = pcall(require, tuneModule)
		if ok and type(t) == "table" and t.Config then
			config = tostring(t.Config)
		end
	end

	local wheelParts, wheelDesc = {}, {}
	if wheelsFolder then
		for _, p in wheelsFolder:GetChildren() do
			if p:IsA("BasePart") and WHEEL_NAMES[p.Name] then
				wheelParts[p.Name] = p
				for _, d in p:GetDescendants() do
					wheelDesc[d] = true
				end
			end
		end
	end
	local function isWheel(d)
		return wheelParts[d.Name] == d or wheelDesc[d] == true
	end

	-- корень: PrimaryPart или самая большая не-колесо
	local root = car.PrimaryPart
	if not (root and root:IsA("BasePart")) or isWheel(root) then
		local best
		for _, d in car:GetDescendants() do
			if d:IsA("BasePart") and not isWheel(d) then
				if not best or volume(d) > volume(best) then best = d end
			end
		end
		root = best
	end
	if not root then
		return nil, "не нашёл корневую часть"
	end
	car.PrimaryPart = root

	-- сварить всё: декор — к корню, внутренности колеса — к своей ступице
	for _, d in car:GetDescendants() do
		if d:IsA("BasePart") then
			if wheelDesc[d] then
				local hub = d
				while hub.Parent and not wheelParts[hub.Name] do
					hub = hub.Parent
				end
				if hub ~= d and wheelParts[hub.Name] then
					local w = Instance.new("WeldConstraint")
					w.Part0 = d
					w.Part1 = hub
					w.Parent = d
				end
			elseif wheelParts[d.Name] ~= d and d ~= root then
				local w = Instance.new("WeldConstraint")
				w.Part0 = d
				w.Part1 = root
				w.Parent = d
			end
		end
	end

	-- якоря долой (всё сварено — не разлетится), декор без столкновений:
	-- машина едет на колёсах, а не брюхом
	for _, d in car:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			if not (wheelParts[d.Name] == d or wheelDesc[d]) then
				d.CanCollide = false
			end
		end
	end

	-- мотор-хинжи колёс: ось = X колеса (ось цилиндра)
	local created = {}
	for name, wp in pairs(wheelParts) do
		if not wp:IsA("MeshPart") then
			wp.Shape = Enum.PartType.Cylinder
		end
		local a0 = Instance.new("Attachment")
		a0.CFrame = root.CFrame:ToObjectSpace(wp.CFrame)
		a0.Parent = root
		local a1 = Instance.new("Attachment")
		a1.Parent = wp
		local h = Instance.new("HingeConstraint")
		h.Name = "#AV"
		h.Attachment0 = a0
		h.Attachment1 = a1
		h.ActuatorType = Enum.ActuatorType.Motor
		h.MotorMaxTorque = 0
		h.AngularVelocity = 0
		h.Parent = wp
		created[name] = h
	end

	-- держатель курса: не переворачивается и едет прямо (драг!)
	local af = Instance.new("Attachment")
	af.Parent = root
	local ao = Instance.new("AlignOrientation")
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = af
	ao.MaxTorque = 1e9
	ao.MaxAngularVelocity = 25
	ao.Responsiveness = 15
	ao.CFrame = root.CFrame.Rotation
	ao.Parent = root

	return {
		root = root,
		wheels = created,
		config = config,
	}
end

return CarPhysics
